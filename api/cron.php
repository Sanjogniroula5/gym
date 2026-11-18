<?php
// Run once a day at 9:00.
// cPanel cron:  /usr/local/bin/php /home/USER/public_html/gym_api/cron.php
// XAMPP test:   http://localhost/gym_api/cron.php?key=YOUR_CRON_KEY
require __DIR__ . '/lib.php';
if (php_sapi_name() !== 'cli' && ($_GET['key'] ?? '') !== CRON_KEY) { http_response_code(403); exit('Forbidden'); }

$in2  = date('Y-m-d', strtotime('+2 days'));
$yday = date('Y-m-d', strtotime('-1 day'));

// 1) membership ends in 2 days
foreach (q('SELECT * FROM members WHERE active=1 AND reminder_sent=0 AND expiry_date=?', [$in2])->fetchAll() as $m) {
    if (wa($m['phone'], 'membership_reminder', [$m['name'], $m['expiry_date']]))
        q('UPDATE members SET reminder_sent=1 WHERE id=?', [$m['id']]);
}
// 2) membership expired yesterday
foreach (q('SELECT * FROM members WHERE active=1 AND expired_msg_sent=0 AND expiry_date=?', [$yday])->fetchAll() as $m) {
    if (wa($m['phone'], 'membership_expired', [$m['name']]))
        q('UPDATE members SET expired_msg_sent=1 WHERE id=?', [$m['id']]);
}
// 3) birthdays
foreach (q('SELECT * FROM members WHERE active=1 AND birthday=?', [date('m-d')])->fetchAll() as $m) {
    wa($m['phone'], 'birthday_wish', [$m['name']]);
}
echo "Done\n";
