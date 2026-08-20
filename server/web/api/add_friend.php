<?php
// SilphNet - send a friend request by Trainer ID. Requires a valid token.
// POST: token, trainer_id  (5-digit string or plain int, e.g. "04815" or 4815)
// Looks up trainer_id in `accounts` to resolve it to an account_id, then
// inserts a pending row. Trainer ID (not name) is the add-friend key so
// this can be done entirely with in-game digit entry - no text typing.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();
$trainerIdRaw = trim($_POST['trainer_id'] ?? $_GET['trainer_id'] ?? '');
if ($trainerIdRaw === '' || !preg_match('/^\d{1,5}$/', $trainerIdRaw)) {
    silphnet_error('trainer_id must be 1-5 digits');
}
$trainerId = (int)$trainerIdRaw;
if ($trainerId < 0 || $trainerId > 65535) silphnet_error('trainer_id out of range');

try {
    $pdo = silphnet_db();

    $lookup = $pdo->prepare('SELECT account_id, name FROM accounts WHERE trainer_id = :tid LIMIT 1');
    $lookup->execute([':tid' => $trainerId]);
    $row = $lookup->fetch();
    if (!$row) silphnet_error('no account with that trainer ID', 404);
    $friendId = $row['account_id'];

    if ($friendId === $account['account_id']) silphnet_error('cannot friend yourself');

    $stmt = $pdo->prepare(
        'INSERT IGNORE INTO friends (account_id, friend_id, status, created_at)
         VALUES (:a, :b, "pending", NOW())'
    );
    $stmt->execute([':a' => $account['account_id'], ':b' => $friendId]);
    silphnet_json(['ok' => true, 'name' => $row['name']]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
