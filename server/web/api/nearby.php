<?php
// SilphNet - who else (friend or not) is currently online AND on the same
// map as you right now. This is friends.php's cousin without the
// friends-only filter, scoped to one map instead of "everywhere a friend
// last was" - the Pokemon-Go-style "who's about" feature.
//
// POST: token, map_id
// Returns: {"ok":true,"nearby":[{"account_id","name","trainer_id"}, ...]}
// Never includes the caller's own account_id, and only ever includes
// players who are actually ONLINE (same 300s/5min threshold as
// everywhere else) - a stale presence row on the right map but long
// offline should not show up as "nearby".

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

const SILPHNET_ONLINE_AFTER_SECONDS = 300;

$account = silphnet_require_token();

$mapId = trim($_POST['map_id'] ?? $_GET['map_id'] ?? '');
if ($mapId === '') silphnet_error('missing required field: map_id');
$mapId = substr($mapId, 0, 64);

try {
    $pdo = silphnet_db();
    $stmt = $pdo->prepare(
        'SELECT p.account_id, a.name, a.trainer_id
         FROM presence p
         JOIN accounts a ON a.account_id = p.account_id
         WHERE p.map_id = :map_id
           AND p.account_id != :me
           AND p.last_seen >= NOW() - INTERVAL ' . SILPHNET_ONLINE_AFTER_SECONDS . ' SECOND
         GROUP BY p.account_id, a.name, a.trainer_id
         ORDER BY a.name ASC'
    );
    $stmt->execute([':map_id' => $mapId, ':me' => $account['account_id']]);
    $rows = $stmt->fetchAll();
    foreach ($rows as &$r) $r['trainer_id'] = str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT);
    silphnet_json(['ok' => true, 'nearby' => $rows]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
