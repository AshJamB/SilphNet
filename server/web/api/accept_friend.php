<?php
// SilphNet - accept an incoming friend request. Requires a valid token.
// POST: token, requester_name
// Flips the pending row to accepted AND inserts the reverse row as
// accepted too, so a friendship works both directions from one accept.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account       = silphnet_require_token();
$requesterName = trim($_POST['requester_name'] ?? $_GET['requester_name'] ?? '');
if ($requesterName === '') silphnet_error('missing requester_name');
$requesterName = substr($requesterName, 0, 16);

$pdo = null;
try {
    $pdo = silphnet_db();

    $lookup = $pdo->prepare('SELECT account_id FROM accounts WHERE name = :name LIMIT 1');
    $lookup->execute([':name' => $requesterName]);
    $row = $lookup->fetch();
    if (!$row) silphnet_error('no account with that name', 404);
    $requesterId = $row['account_id'];

    $check = $pdo->prepare(
        'SELECT id FROM friends WHERE account_id = :req AND friend_id = :me AND status = "pending"'
    );
    $check->execute([':req' => $requesterId, ':me' => $account['account_id']]);
    if (!$check->fetch()) silphnet_error('no pending request from that name', 404);

    $pdo->beginTransaction();
    $pdo->prepare('UPDATE friends SET status = "accepted" WHERE account_id = :req AND friend_id = :me')
        ->execute([':req' => $requesterId, ':me' => $account['account_id']]);
    $pdo->prepare(
        'INSERT INTO friends (account_id, friend_id, status, created_at) VALUES (:me, :req, "accepted", NOW())
         ON DUPLICATE KEY UPDATE status = "accepted"'
    )->execute([':me' => $account['account_id'], ':req' => $requesterId]);
    $pdo->commit();

    silphnet_json(['ok' => true]);
} catch (PDOException $e) {
    if ($pdo && $pdo->inTransaction()) $pdo->rollBack();
    silphnet_error('db error', 500);
}
