<?php
// SilphNet - shared token-check helper used by every endpoint that needs
// to know who's calling (ping.php, friends.php, add_friend.php, etc.).
// Centralised here so there's exactly one place that decides what counts
// as a valid session, rather than each endpoint re-implementing the same
// SELECT and getting subtly out of sync.

require_once __DIR__ . '/db.php';

// Looks up the token from POST (or GET, for read-only endpoints like
// friends.php) and returns ['account_id' => ..., 'name' => ...], or exits
// the request with a 401 JSON error if the token is missing/invalid.
function silphnet_require_token() {
    $token = trim($_POST['token'] ?? $_GET['token'] ?? '');
    if ($token === '') silphnet_error('missing token', 401);

    $pdo = silphnet_db();
    $stmt = $pdo->prepare(
        'SELECT s.account_id, a.name FROM sessions s
         JOIN accounts a ON a.account_id = s.account_id
         WHERE s.token = :token'
    );
    $stmt->execute([':token' => $token]);
    $row = $stmt->fetch();
    if (!$row) silphnet_error('token not recognised', 401);
    return $row;
}
