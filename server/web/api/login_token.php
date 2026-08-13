<?php
// SilphNet accounts - re-authenticate with a cached session token instead
// of typing name+password again. Same role the old TCP server's TOK|
// login played - the mod caches whatever token register.php/login.php
// last returned (in mod.save, same as before) and uses this on every
// later launch so you don't have to log in every time.
// POST: token
// Returns: {"ok":true,"account_id":"...","name":"...","trainer_id":"04815"}
//
// Goes through the shared silphnet_require_token() (auth.php) rather than
// its own separate query, so this endpoint gets the same expiry handling
// as every other authenticated one for free: a session unused for more
// than SILPHNET_SESSION_MAX_AGE_DAYS is rejected and deleted here rather
// than being trusted forever, and an active one has its last_used bumped.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();   // exits with 401 if invalid/expired

try {
    $pdo = silphnet_db();
    $stmt = $pdo->prepare('SELECT trainer_id FROM accounts WHERE account_id = :id');
    $stmt->execute([':id' => $account['account_id']]);
    $row = $stmt->fetch();
    if (!$row) silphnet_error('account not found', 401);

    silphnet_json([
        'ok' => true, 'account_id' => $account['account_id'], 'name' => $account['name'],
        'trainer_id' => str_pad($row['trainer_id'], 5, '0', STR_PAD_LEFT),
    ]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
