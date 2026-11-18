<?php
require __DIR__ . '/lib.php';

header('Access-Control-Allow-Origin: *');   // in production, put your website's address instead of *
header('Access-Control-Allow-Headers: Content-Type, X-Auth-Token');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }

try {
    route($_GET['r'] ?? '');
} catch (Throwable $e) {
    error_log($e);
    fail('Server error', 500);
}

function route(string $r) {
    $today = date('Y-m-d');

    switch ($r) {
        // ------------------------------------------------------------ login
        case 'login':
            $b = body();
            $u = q('SELECT * FROM users WHERE login_id=?', [trim($b['login_id'] ?? '')])->fetch();
            if (!$u || !password_verify($b['password'] ?? '', $u['password_hash'])) {
                sleep(1);
                fail('Wrong ID or password', 401);
            }
            if ($u['role'] === 'member') {
                $m = q('SELECT active FROM members WHERE user_id=?', [$u['id']])->fetch();
                if (!$m || !$m['active']) fail('Your account is deactivated. Please contact the gym.', 401);
            }
            out(['token' => jwt_make(['uid' => (int)$u['id'], 'role' => $u['role']], 7 * 86400), 'role' => $u['role']]);

        // -------------------------------------------------------- dashboard
        case 'dashboard':
            auth('admin');
            $t = q('SELECT COUNT(*) c, SUM(expiry_date < ?) expired, SUM(status=\'unpaid\') unpaid FROM members WHERE active=1', [$today])->fetch();
            out([
                'total' => (int)$t['c'],
                'expired' => (int)$t['expired'],
                'active' => (int)$t['c'] - (int)$t['expired'],
                'unpaid' => (int)$t['unpaid'],
                'checkins' => (int)q('SELECT COUNT(*) FROM attendance WHERE day=?', [$today])->fetchColumn(),
                'revenue' => (int)q('SELECT COALESCE(SUM(amount),0) FROM payments WHERE paid_at >= ?', [date('Y-m-01') . ' 00:00:00'])->fetchColumn(),
                'renew_requests' => q('SELECT m.id, m.name, m.phone FROM renew_requests r JOIN members m ON m.id=r.member_id WHERE r.seen=0')->fetchAll(),
            ]);

        // ---------------------------------------------------------- members
        case 'members':
            auth('admin');
            out(['members' => members_all()]);

        case 'member_create':
            auth('admin');
            $b = body();
            $name = trim($b['name'] ?? '');
            $phone = preg_replace('/\D/', '', $b['phone'] ?? '');
            $exp = $b['expiry_date'] ?? '';
            if ($name === '' || strlen($phone) < 10 || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $exp))
                fail('Name, phone and expiry date are required');
            $bd = trim($b['birthday'] ?? '');
            if ($bd !== '' && !preg_match('/^\d{2}-\d{2}$/', $bd)) fail('Birthday must be MM-DD');
            $paid = ($b['status'] ?? '') === 'paid';
            $months = max(1, (int)($b['duration_months'] ?? 1));
            $pw = gen_pass();

            $pdo = db();
            $pdo->beginTransaction();
            try {
                q('INSERT INTO users(login_id,password_hash,role) VALUES(?,?,?)', [$phone, password_hash($pw, PASSWORD_DEFAULT), 'member']);
                $uid = $pdo->lastInsertId();
                q('INSERT INTO members(user_id,name,address,phone,birthday,duration_months,expiry_date,status) VALUES(?,?,?,?,?,?,?,?)',
                  [$uid, $name, trim($b['address'] ?? ''), $phone, $bd ?: null, $months, $exp, $paid ? 'paid' : 'unpaid']);
                $mid = (int)$pdo->lastInsertId();
                if ($paid) add_payment($mid, (int)($b['amount'] ?? 0), $b['method'] ?? 'Cash'); // no thank-you on joining
                $pdo->commit();
            } catch (PDOException $e) {
                $pdo->rollBack();
                if ($e->getCode() === '23000') fail('A member with this phone already exists', 409);
                throw $e;
            }
            wa($phone, 'gym_welcome', [$name, $phone, $pw]);
            out(['login_id' => $phone, 'password' => $pw]);

        case 'member_update':
            auth('admin');
            $b = body();
            $m = mem_get((int)($b['id'] ?? 0));
            $bd = trim($b['birthday'] ?? '');
            if ($bd !== '' && !preg_match('/^\d{2}-\d{2}$/', $bd)) fail('Birthday must be MM-DD');
            q('UPDATE members SET name=?, address=?, phone=?, birthday=? WHERE id=?',
              [trim($b['name'] ?? $m['name']), trim($b['address'] ?? ''), preg_replace('/\D/', '', $b['phone'] ?? $m['phone']), $bd ?: null, $m['id']]);
            out(['ok' => true]);

        case 'member_active':
            auth('admin');
            $b = body();
            $m = mem_get((int)($b['id'] ?? 0));
            q('UPDATE members SET active=? WHERE id=?', [empty($b['active']) ? 0 : 1, $m['id']]);
            out(['ok' => true]);

        case 'member_pay':
            auth('admin');
            $b = body();
            $m = mem_get((int)($b['id'] ?? 0));
            $amt = (int)($b['amount'] ?? 0);
            if ($amt <= 0) fail('Enter the amount');
            q("UPDATE members SET status='paid' WHERE id=?", [$m['id']]);
            add_payment((int)$m['id'], $amt, $b['method'] ?? 'Cash');
            wa($m['phone'], 'payment_thanks', [$m['name'], $amt]);
            out(['ok' => true]);

        case 'member_renew':
            auth('admin');
            $b = body();
            $m = mem_get((int)($b['id'] ?? 0));
            $amt = (int)($b['amount'] ?? 0);
            $months = max(1, (int)($b['months'] ?? 1));
            if ($amt <= 0) fail('Enter the amount');
            $base = max($m['expiry_date'], $today);           // extend from old expiry, or from today if expired
            $new = date('Y-m-d', strtotime("$base +$months months"));
            q("UPDATE members SET expiry_date=?, duration_months=?, status='paid', reminder_sent=0, expired_msg_sent=0 WHERE id=?",
              [$new, $months, $m['id']]);
            add_payment((int)$m['id'], $amt, $b['method'] ?? 'Cash');
            wa($m['phone'], 'payment_thanks', [$m['name'], $amt]);
            out(['expiry_date' => $new]);

        case 'member_reset':
            auth('admin');
            $b = body();
            $m = mem_get((int)($b['id'] ?? 0));
            $pw = gen_pass();
            q('UPDATE users SET password_hash=? WHERE id=?', [password_hash($pw, PASSWORD_DEFAULT), $m['user_id']]);
            out(['login_id' => $m['login_id'], 'password' => $pw]);

        case 'checkin':
            auth('admin');
            $b = body();
            $m = mem_get((int)($b['id'] ?? 0));
            q('INSERT IGNORE INTO attendance(member_id,day) VALUES(?,?)', [$m['id'], $today]);
            out(['expired' => $m['expiry_date'] < $today]);

        case 'renew_seen':
            auth('admin');
            $b = body();
            q('UPDATE renew_requests SET seen=1 WHERE member_id=?', [(int)($b['id'] ?? 0)]);
            out(['ok' => true]);

        // ----------------------------------------------------- Excel (CSV)
        case 'export_token':
            auth('admin');
            out(['token' => jwt_make(['uid' => 0, 'role' => 'admin'], 120)]); // valid for 2 minutes

        case 'export':
            auth('admin', true);
            header('Content-Type: text/csv; charset=utf-8');
            header('Content-Disposition: attachment; filename="members_' . $today . '.csv"');
            echo "\xEF\xBB\xBF"; // so Excel reads UTF-8 correctly
            $f = fopen('php://output', 'w');
            $row = fn(array $x) => fputcsv($f, $x, ',', '"', '\\');
            $row(['Name', 'Phone', 'Address', 'Months', 'Expiry', 'Status', 'Days Left', 'Active']);
            foreach (members_all() as $m) {
                $left = (new DateTime($today))->diff(new DateTime($m['expiry_date']))->format('%r%a');
                $row([$m['name'], $m['phone'], $m['address'], $m['duration_months'], $m['expiry_date'],
                      $m['status'], $left, $m['active'] ? 'yes' : 'no']);
            }
            exit;

        // ----------------------------------------------------------- member
        case 'me':
            $p = auth('member');
            $m = q('SELECT m.*, u.login_id FROM members m JOIN users u ON u.id=m.user_id WHERE m.user_id=?', [$p['uid']])->fetch();
            if (!$m || !$m['active']) fail('Your account is deactivated', 401);
            out([
                'member' => mem($m),
                'payments' => q('SELECT amount, method, paid_at FROM payments WHERE member_id=? ORDER BY paid_at DESC', [$m['id']])->fetchAll(),
                'renew_pending' => (bool)q('SELECT 1 FROM renew_requests WHERE member_id=? AND seen=0', [$m['id']])->fetchColumn(),
            ]);

        case 'renew_request':
            $p = auth('member');
            $m = q('SELECT id FROM members WHERE user_id=? AND active=1', [$p['uid']])->fetch();
            if (!$m) fail('Account not found', 401);
            q('INSERT INTO renew_requests(member_id,seen) VALUES(?,0) ON DUPLICATE KEY UPDATE seen=0, created_at=NOW()', [$m['id']]);
            out(['ok' => true]);

        default:
            fail('Unknown route', 404);
    }
}
