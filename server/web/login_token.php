<?php
// SilphNet accounts - re-authenticate with a cached session token instead
// of typing name+password again. Same role the old TCP server's TOK|
// login played - the mod caches whatever token register.php/login.php
// last returned (in mod.save, same as before) and uses this on every
// later launch so you don't have to log in every time.
// POST: token
// Returns: {"ok":true,"account_id":"...","name":"...","trainer_id":"04815"}

require __DIR__ . '/db.php';

$token = trim($_POST['token'] ?? '');
if ($token === '') silphnet_error('missing token');

try {
    $pdo = silphnet_db();
    $stmt = $pdo->prepare(
        'SELECT s.account_id, a.name, a.trainer_id FROM sessions s
         JOIN accounts a ON a.account_id = s.account_id
         WHERE s.token = :token'
    );
    $stmt->execute([':token' => $token]);
    $row = $stmt->fetch();
    if (!$row) silphnet_error('token not recognised', 401);

    silphnet_json([
        'ok' => true, 'account_id' => $row['account_id'], 'name' => $row['name'],
        'trainer_id' => str_pad($row['trainer_id'], 5, '0', STR_PAD_LEFT),
    ]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
