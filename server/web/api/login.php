<?php
// SilphNet accounts - log in with an existing name + password.
// POST: name, password
// Returns: {"ok":true,"account_id":"...","token":"...","trainer_id":"04815"}
// (a fresh session token every login - old ones stay valid too, same "up
// to N devices" spirit the old TCP server had, just not capped here since
// sessions are cheap rows rather than an in-memory list capped at 5).

require __DIR__ . '/db.php';

$name     = trim($_POST['name'] ?? '');
$password = (string)($_POST['password'] ?? '');
if ($name === '' || $password === '') silphnet_error('missing name or password');

try {
    $pdo = silphnet_db();

    $stmt = $pdo->prepare('SELECT account_id, password_hash, trainer_id FROM accounts WHERE name = :name');
    $stmt->execute([':name' => $name]);
    $row = $stmt->fetch();

    if (!$row || !password_verify($password, $row['password_hash'])) {
        // Same error for "no such name" and "wrong password" - don't leak
        // which one it was, so a login attempt can't be used to enumerate
        // valid names.
        silphnet_error('wrong name or password', 401);
    }

    $token = bin2hex(random_bytes(32));
    $pdo->prepare('INSERT INTO sessions (token, account_id, created_at, last_used) VALUES (:token, :id, NOW(), NOW())')
        ->execute([':token' => $token, ':id' => $row['account_id']]);

    silphnet_json([
        'ok' => true, 'account_id' => $row['account_id'], 'token' => $token,
        'trainer_id' => str_pad($row['trainer_id'], 5, '0', STR_PAD_LEFT),
    ]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
