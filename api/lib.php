<?php
require __DIR__ . '/config.php';
date_default_timezone_set('Asia/Kathmandu');

// ---------- database
function db(): PDO {
    static $p;
    if (!$p) {
        $p = new PDO('mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4', DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
        $p->exec("SET time_zone='+05:45'");
    }
    return $p;
}
function q(string $sql, array $args = []): PDOStatement {
    $s = db()->prepare($sql);
    $s->execute($args);
    return $s;
}

// ---------- http helpers
function out($data, int $code = 200) {
    http_response_code($code);
    header('Content-Type: application/json');
    echo json_encode($data);
    exit;
}
function fail(string $msg, int $code = 400) { out(['error' => $msg], $code); }
function body(): array { return json_decode(file_get_contents('php://input'), true) ?: []; }

// ---------- JWT (HS256)
function b64u(string $s): string { return rtrim(strtr(base64_encode($s), '+/', '-_'), '='); }
function jwt_make(array $p, int $ttl): string {
    $p['exp'] = time() + $ttl;
    $h = b64u(json_encode(['alg' => 'HS256', 'typ' => 'JWT']));
    $b = b64u(json_encode($p));
    return "$h.$b." . b64u(hash_hmac('sha256', "$h.$b", JWT_SECRET, true));
}
function jwt_read(string $t): ?array {
    $x = explode('.', $t);
    if (count($x) !== 3) return null;
    [$h, $b, $s] = $x;
    if (!hash_equals(b64u(hash_hmac('sha256', "$h.$b", JWT_SECRET, true)), $s)) return null;
    $p = json_decode(base64_decode(strtr($b, '-_', '+/')), true);
    return ($p && ($p['exp'] ?? 0) >= time()) ? $p : null;
}
function auth(?string $role = null, bool $allowQuery = false): array {
    $t = $_SERVER['HTTP_X_AUTH_TOKEN'] ?? ($allowQuery ? ($_GET['token'] ?? '') : '');
    $p = jwt_read($t);
    if (!$p) fail('Please log in again', 401);
    if ($role && $p['role'] !== $role) fail('Not allowed', 403);
    return $p;
}

// ---------- helpers
function gen_pass(): string {
    $a = 'abcdefghjkmnpqrstuvwxyz23456789';
    $s = '';
    for ($i = 0; $i < 8; $i++) $s .= $a[random_int(0, strlen($a) - 1)];
    return $s;
}
function add_payment(int $memberId, int $amount, string $method): void {
    if (!in_array($method, ['Cash', 'eSewa', 'Khalti', 'Bank'], true)) $method = 'Cash';
    q('INSERT INTO payments(member_id,amount,method,paid_at) VALUES(?,?,?,?)',
      [$memberId, $amount, $method, date('Y-m-d H:i:s')]);
}
function mem_get(int $id): array {
    $m = q('SELECT m.*, u.login_id FROM members m JOIN users u ON u.id=m.user_id WHERE m.id=?', [$id])->fetch();
    if (!$m) fail('Member not found', 404);
    return $m;
}
function mem(array $r): array {
    return [
        'id' => (int)$r['id'], 'name' => $r['name'], 'address' => $r['address'],
        'phone' => $r['phone'], 'login_id' => $r['login_id'], 'birthday' => $r['birthday'] ?? '',
        'duration_months' => (int)$r['duration_months'], 'expiry_date' => $r['expiry_date'],
        'status' => $r['status'], 'active' => (bool)$r['active'],
    ];
}
function members_all(): array {
    return array_map('mem', q('SELECT m.*, u.login_id FROM members m JOIN users u ON u.id=m.user_id ORDER BY m.expiry_date')->fetchAll());
}

// ---------- WhatsApp Cloud API (approved template with body variables)
function wa(string $to, string $template, array $params): bool {
    if (!WA_TOKEN || !WA_PHONE_ID) return false;
    $payload = [
        'messaging_product' => 'whatsapp', 'to' => $to, 'type' => 'template',
        'template' => [
            'name' => $template, 'language' => ['code' => 'en'],
            'components' => [[
                'type' => 'body',
                'parameters' => array_map(fn($t) => ['type' => 'text', 'text' => (string)$t], $params),
            ]],
        ],
    ];
    $ch = curl_init('https://graph.facebook.com/v20.0/' . WA_PHONE_ID . '/messages');
    curl_setopt_array($ch, [
        CURLOPT_POST => 1, CURLOPT_RETURNTRANSFER => 1, CURLOPT_TIMEOUT => 10,
        CURLOPT_HTTPHEADER => ['Authorization: Bearer ' . WA_TOKEN, 'Content-Type: application/json'],
        CURLOPT_POSTFIELDS => json_encode($payload),
    ]);
    $res = curl_exec($ch);
    $ok = curl_getinfo($ch, CURLINFO_HTTP_CODE) < 300;
    curl_close($ch);
    if (!$ok) error_log("WhatsApp $template -> $to failed: $res");
    return $ok;
}
