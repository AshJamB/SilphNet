<?php
// SilphNet - remove an accepted friend (or cancel/decline a pending request
// either direction). Requires a valid token.
// POST: token, account_id  (the OTHER account's id - see friends.php's
//       "account_id" field for accepted friends, or pending_requests.php's
//       entry for an incoming request you want to decline instead of accept)
//
// Deletes BOTH rows of the pair (whichever exist) in one transaction, same
// reasoning as accept_friend.php inserting both directions on accept - a
// completed friendship is two rows (one per direction, see schema.sql), so
// removing it needs to clear both, or the other person would still see you
// as an accepted friend while you no longer see them. Also covers deleting
// a single one-directional pending row (decline an incoming request, or
// cancel one you sent) - whichever rows actually exist just get removed;
// a request that was never accepted only ever had one row to begin with.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();
$otherId = trim($_POST['account_id'] ?? '');
if ($otherId === '') silphnet_error('missing account_id');
// Same shape as every other account_id in this API (see register.php) -
// not a trust boundary, just rejects obviously malformed input early.
if (!preg_match('/^[A-F0-9]{8}$/', $otherId)) silphnet_error('malformed account_id');

try {
    $pdo = silphnet_db();
    $pdo->beginTransaction();
    $del = $pdo->prepare(
        'DELETE FROM friends
         WHERE (account_id = :me AND friend_id = :other)
            OR (account_id = :other AND friend_id = :me)'
    );
    $del->execute([':me' => $account['account_id'], ':other' => $otherId]);
    $removed = $del->rowCount();
    $pdo->commit();

    if ($removed === 0) silphnet_error('no friendship or request with that account', 404);
    silphnet_json(['ok' => true, 'removed' => $removed]);
} catch (PDOException $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    silphnet_error('db error', 500);
}
