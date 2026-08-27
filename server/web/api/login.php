<?php
// SilphNet accounts - log in with an existing name + password.
// POST: name, password
// Returns: {"ok":true,"account_id":"...","token":"...","trainer_id":"04815","has_email":"true"|"false"}
// (a fresh session token every login - old ones stay valid too, same "up
// to N devices" spirit the old TCP server had, just not capped here since
// sessions are cheap rows rather than an in-memory list capped at 5).
//
// has_email is a QUOTED STRING ("true"/"false"), not a real JSON boolean -
// deliberately matching this project's existing convention for a
// boolean-shaped field the MOD reads (e.g. online_by_version.php's
// is_you), because main.lua's login/login_token/register handling reads
// this response through jsonField(), which only understands a quoted
// string or a bare number - a real unquoted JSON true/false would silently
// come back nil there. Never the actual email address itself - this
// endpoint has no reason to ever decrypt or return that, only whether one
// exists, so the mod can show its "SN RECOVER ACCT" Start Menu row for an
// account that has none (built directly for a real reported case: a
// player locked out of a Gen 2 save with no recovery email and no
// self-service way back in).

require __DIR__ . '/db.php';

$name     = trim($_POST['name'] ?? '');
$password = (string)($_POST['password'] ?? '');
if ($name === '' || $password === '') silphnet_error('missing name or password');

try {
    $pdo = silphnet_db();

    $stmt = $pdo->prepare('SELECT account_id, password_hash, trainer_id, email FROM accounts WHERE name = :name');
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
        'has_email' => ($row['email'] !== null) ? 'true' : 'false',
    ]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
