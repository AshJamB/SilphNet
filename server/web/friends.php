<?php
// SilphNet - last-known positions of your accepted friends, across ALL
// their active game_versions (one row per friend per save they've pinged
// from). Requires a valid token now (was a bare account_id before).
// GET: token
// Returns: {"ok":true,"friends":[{"account_id","name","trainer_id",
//           "game_version","map_id","x","y","facing","last_seen"}, ...]}
//
// LEFT JOINs presence (not an inner join) so a friend who's accepted but
// hasn't pinged yet still shows up - with null map_id/x/y/last_seen,
// which the mod treats as "never seen" rather than hiding them entirely.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();

try {
    $pdo = silphnet_db();
    $stmt = $pdo->prepare(
        'SELECT a.account_id, a.name, a.trainer_id, p.game_version, p.map_id, p.x, p.y, p.facing, p.last_seen
         FROM friends f
         JOIN accounts a ON a.account_id = f.friend_id
         LEFT JOIN presence p ON p.account_id = f.friend_id
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
