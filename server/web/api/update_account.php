<?php
// SilphNet accounts - rename the caller's own username and/or reassign
// their own Trainer ID. The one endpoint on this whole server that can
// change identity-bearing account fields, so it's held to a higher bar
// than a normal token-gated endpoint: token proves "this session is
// still logged in", but the password is re-checked here too, same as a
// fresh login, before anything is written - a stolen/leaked session
// token alone (e.g. a cached mod.save token on a shared device) isn't
// enough on its own to change what account you log in as or which
// Trainer ID your friends see.
//
// POST: token, password, [name], [trainer_id]
// At least one of name/trainer_id must be given. Both are optional
// together, same "at least one of several optional fields" shape as
// stats.php's hasStats/activity split.
//
// Returns: {"ok":true,"name":"...","trainer_id":"04815"} - the account's
// resulting name/trainer_id after the update, so the calling page can
// refresh its display from the authoritative server value rather than
// just trusting back whatever it sent.
//
// Every check here is a REAL re-check against the database at write
// time, not a trust of whatever check_name.php/check_trainer_id.php
// said earlier - those two are just live typing feedback; a gap between
// "checked available" and "hit save" (another tab, another device,
// someone else grabbing the same name a second earlier) is real and
// must be caught here too, inside the same transaction that performs
// the write, or two people could both be told "yes" and only one
// actually end up with it.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();

$password = (string)($_POST['password'] ?? '');
if ($password === '') silphnet_error('password required to change account details', 401);

$wantsName = array_key_exists('name', $_POST);
$wantsTrainerId = array_key_exists('trainer_id', $_POST);
if (!$wantsName && !$wantsTrainerId) {
    silphnet_error('nothing to update: provide name and/or trainer_id');
}

$newName = null;
if ($wantsName) {
    $newName = trim($_POST['name']);
    if ($newName === '') silphnet_error('name cannot be empty');
    if (strlen($newName) > 16) silphnet_error('name too long (max 16)');
    if (preg_match('/[|;,\r\n]/', $newName)) silphnet_error('name contains invalid characters');
}

$newTrainerId = null;
if ($wantsTrainerId) {
    $rawTid = trim((string)$_POST['trainer_id']);
    if ($rawTid === '' || !ctype_digit($rawTid)) silphnet_error('trainer_id must be a number');
    $newTrainerId = (int)$rawTid;
    if ($newTrainerId < 0 || $newTrainerId > 65535) silphnet_error('trainer_id must be 0-65535');
}

try {
    $pdo = silphnet_db();

    // Re-verify the password against THIS account's own hash - not just
    // "a valid token exists", the actual password, fetched fresh here
    // rather than reused from whatever silphnet_require_token() already
    // confirmed (that only checked the session token, never the
    // password itself).
    $stmt = $pdo->prepare('SELECT password_hash FROM accounts WHERE account_id = :id');
    $stmt->execute([':id' => $account['account_id']]);
    $row = $stmt->fetch();
    if (!$row || !password_verify($password, $row['password_hash'])) {
        silphnet_error('wrong password', 401);
    }

    // Both uniqueness re-checks AND the write happen inside one
    // transaction, so a second request for the same name/id landing in
    // the gap between "we checked" and "we wrote" can't slip through -
    // the second request's own re-check (once it gets the row lock)
    // will see the first request's write and correctly reject.
    $pdo->beginTransaction();

    if ($wantsName) {
        $check = $pdo->prepare('SELECT account_id FROM accounts WHERE name = :name AND account_id != :me FOR UPDATE');
        $check->execute([':name' => $newName, ':me' => $account['account_id']]);
        if ($check->fetch()) {
            $pdo->rollBack();
            silphnet_error('that name is taken', 409);
        }
    }
    if ($wantsTrainerId) {
        $check = $pdo->prepare('SELECT account_id FROM accounts WHERE trainer_id = :tid AND account_id != :me FOR UPDATE');
        $check->execute([':tid' => $newTrainerId, ':me' => $account['account_id']]);
        if ($check->fetch()) {
            $pdo->rollBack();
            silphnet_error('that Trainer ID is taken', 409);
        }
    }

    $sets = [];
    $params = [':me' => $account['account_id']];
    if ($wantsName) { $sets[] = 'name = :name'; $params[':name'] = $newName; }
    if ($wantsTrainerId) { $sets[] = 'trainer_id = :tid'; $params[':tid'] = $newTrainerId; }
    $pdo->prepare('UPDATE accounts SET ' . implode(', ', $sets) . ' WHERE account_id = :me')->execute($params);

    $pdo->commit();

    $final = $pdo->prepare('SELECT name, trainer_id FROM accounts WHERE account_id = :me');
    $final->execute([':me' => $account['account_id']]);
    $finalRow = $final->fetch();

    silphnet_json([
        'ok' => true,
        'name' => $finalRow['name'],
        'trainer_id' => str_pad($finalRow['trainer_id'], 5, '0', STR_PAD_LEFT),
    ]);
} catch (PDOException $e) {
    // isset() guard, not just $pdo->inTransaction() - if silphnet_db()
    // itself throws (e.g. the connection fails), $pdo is never assigned
    // at all, and calling inTransaction() on an unset variable would be
    // its own fatal error masking the real one. Every other multi-step
    // endpoint in this project only ever has ONE PDO call that could
    // fail before a transaction exists, but this is the first endpoint
    // to use beginTransaction()/rollBack() at all, so this guard is new
    // here rather than copied from an existing pattern.
    if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack();
    silphnet_error('db error', 500);
}
