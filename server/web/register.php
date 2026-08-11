<?php
// SilphNet accounts - create a new account.
// POST: name, password
// Returns: {"ok":true,"account_id":"...","token":"...","trainer_id":"04815"}
//
// trainer_id is a random 5-digit id (00000-65535, same range as the real
// games' 16-bit trainer ID), generated once here and unique across all
// accounts - assigned at registration, never changes afterward.
//
// Password is hashed with PHP's password_hash() (bcrypt) before it ever
// touches the database - only the hash is stored, and password_verify()
// is the only way to check a guess against it. There is no way to recover
// or view the original password, by design - not from a DB dump, not by
// anyone with admin access, including you.

require __DIR__ . '/db.php';

$name     = trim($_POST['name'] ?? '');
$password = (string)($_POST['password'] ?? '');

if ($name === '' || $password === '') silphnet_error('missing name or password');
if (strlen($name) > 16) silphnet_error('name too long (max 16)');
if (strlen($password) < 4) silphnet_error('password too short (min 4)');
// Same sanitization the old TCP server applied - no separators that would
// break the presence/friends wire formats or get confused with wire chars.
if (preg_match('/[|;,\r\n]/', $name)) silphnet_error('name contains invalid characters');

try {
    $pdo = silphnet_db();

    $check = $pdo->prepare('SELECT account_id FROM accounts WHERE name = :name');
    $check->execute([':name' => $name]);
    if ($check->fetch()) silphnet_error('that name is taken', 409);

    // 8 random hex bytes, uppercased - same shape/length as the old TCP
    // server's secrets.token_hex(4).upper() account ids, so anything that
    // still expects that format (logs, manual DB lookups) keeps working.
    do {
        $accountId = strtoupper(bin2hex(random_bytes(4)));
        $collision = $pdo->prepare('SELECT 1 FROM accounts WHERE account_id = :id');
        $collision->execute([':id' => $accountId]);
    } while ($collision->fetch());

    $hash = password_hash($password, PASSWORD_BCRYPT);

    // random_int(0, 65535) matches the 16-bit range the real games use for
    // a trainer ID; retried on the rare collision, same pattern as account_id.
    do {
        $trainerId = random_int(0, 65535);
        $tidCheck = $pdo->prepare('SELECT 1 FROM accounts WHERE trainer_id = :tid');
        $tidCheck->execute([':tid' => $trainerId]);
    } while ($tidCheck->fetch());

    $pdo->prepare('INSERT INTO accounts (account_id, name, password_hash, trainer_id, created_at) VALUES (:id, :name, :hash, :tid, NOW())')
        ->execute([':id' => $accountId, ':name' => $name, ':hash' => $hash, ':tid' => $trainerId]);

    $token = bin2hex(random_bytes(32));
    $pdo->prepare('INSERT INTO sessions (token, account_id, created_at, last_used) VALUES (:token, :id, NOW(), NOW())')
        ->execute([':token' => $token, ':id' => $accountId]);

    silphnet_json(['ok' => true, 'account_id' => $accountId, 'token' => $token, 'trainer_id' => str_pad($trainerId, 5, '0', STR_PAD_LEFT)]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
