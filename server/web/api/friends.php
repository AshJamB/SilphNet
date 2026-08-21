<?php
// SilphNet - last-known positions of your accepted friends, across ALL
// their active game_versions (one row per friend per save they've pinged
// from). Requires a valid token now (was a bare account_id before).
// GET: token
// Returns: {"ok":true,"friends":[{"account_id","name","trainer_id",
//           "game_version","map_id","x","y","facing","last_seen",
//           "badges_mask"}, ...]}
//
// LEFT JOINs presence (not an inner join) so a friend who's accepted but
// hasn't pinged yet still shows up - with null map_id/x/y/last_seen,
// which the mod treats as "never seen" rather than hiding them entirely.
//
// Also LEFT JOINs friend_stats, keyed on BOTH friend_id AND the same
// game_version as the presence row - a friend can have separate badge
// masks per save (RED vs YELLOW, say), and the gym sign feature cares
// about "does this specific in-progress save have this badge", which
// only makes sense paired to the game_version that row's map_id/x/y are
// actually for. COALESCE to 0 (not NULL) since a friend who's pinged but
// never uploaded a stats snapshot for that version has no mask yet -
// main.lua treats "no bits set" the same as "we don't know", which is
// the correct default either way (never show them as having a badge
// they haven't confirmed).
require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();

try {
    $pdo = silphnet_db();
    $stmt = $pdo->prepare(
        'SELECT a.account_id, a.name, a.trainer_id, p.game_version, p.map_id, p.x, p.y, p.facing, p.last_seen,
                COALESCE(fs.badges_mask, 0) AS badges_mask
         FROM friends f
         JOIN accounts a ON a.account_id = f.friend_id
         LEFT JOIN presence p ON p.account_id = f.friend_id
         LEFT JOIN friend_stats fs ON fs.account_id = f.friend_id AND fs.game_version = p.game_version
         WHERE f.account_id = :account_id AND f.status = "accepted"
         ORDER BY p.last_seen DESC'
    );
    $stmt->execute([':account_id' => $account['account_id']]);
    $rows = $stmt->fetchAll();
    foreach ($rows as &$r) $r['trainer_id'] = str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT);
    silphnet_json(['ok' => true, 'friends' => $rows]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
