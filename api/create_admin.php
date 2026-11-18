<?php
// Usage (terminal):  php create_admin.php admin YourStrongPassword
require __DIR__ . '/lib.php';
if (php_sapi_name() !== 'cli') exit('Run from the terminal only');
[$s, $id, $pw] = $argv + [null, null, null];
if (!$id || !$pw) exit("Usage: php create_admin.php admin_id password\n");
q('INSERT INTO users(login_id,password_hash,role) VALUES(?,?,?)', [$id, password_hash($pw, PASSWORD_DEFAULT), 'admin']);
echo "Admin '$id' created\n";
