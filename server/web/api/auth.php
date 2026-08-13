<?php
// SilphNet - shared token-check helper used by every endpoint that needs
// to know who's calling (ping.php, friends.php, add_friend.php, etc.).
// Centralised here so there's exactly one place that decides what counts
// as a valid session, rather than each endpoint re-implementing the same
// SELECT and getting subtly out of sync.

require_once __DIR__ . '/db.php';

// A session unused for this long is treated as abandoned and deleted -
// without this, every real login (not a cached-token reconnect) added a
// sessions row that lived forever, since nothing ever cleaned old ones up.
// An actively-used session never hits this: every successful check here
// bumps last_used, so a device that keeps playing never expires.
const SILPHNET_SESSION_MAX_AGE_DAYS = 90;

// Looks up the token from POST (or GET, for read-only endpoints like
// friends.php) and returns ['account_id' => ..., 'name' => ...], or exits
// the request with a 401 JSON error if the token is missing, invalid, or
// expired (in which case the stale row is also deleted here).
//
// The age check (last_used < NOW() - INTERVAL ... DAY) is done entirely in
// SQL rather than pulled into PHP and compared with strtotime()/time() -
// both last_used and NOW() are written/read by MySQL itself, so comparing
// them in the same query sidesteps any PHP-vs-MySQL timezone mismatch
// entirely, rather than needing the kind of manual UTC-offset correction
// main.lua's parseMysqlDatetimeUtc() has to do on the Lua side.
function silphnet_require_token() {
    $token = trim($_POST['token'] ?? $_GET['token'] ?? '');
    if ($token === '') silphnet_error('missing token', 401);

    $pdo = silphnet_db();
    $maxAge = SILPHNET_SESSION_MAX_AGE_DAYS;
    $stmt = $pdo->prepare(
        "SELECT s.account_id, a.name,
                (s.last_used < NOW() - INTERVAL $maxAge DAY) AS expired
         FROM sessions s
         JOIN accounts a ON a.account_id = s.account_id
         WHERE s.token = :token"
    );
    $stmt->execute([':token' => $token]);
    $row = $stmt->fetch();
    if (!$row) silphnet_error('token not recognised', 401);

    if ((int)$row['expired'] === 1) {
        $pdo->prepare('DELETE FROM sessions WHERE token = :token')->execute([':token' => $token]);
        silphnet_error('session expired', 401);
    }

    $pdo->prepare('UPDATE sessions SET last_used = NOW() WHERE token = :token')->execute([':token' => $token]);
    return $row;
}
