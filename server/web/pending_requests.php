<?php
// SilphNet - list incoming (not yet accepted) friend requests sent TO you.
// GET: token
// Returns: {"ok":true,"requests":[{"name":"BOB","trainer_id":"04815"}, ...]}
//
// Polled on the same schedule as friends.php so the in-game status screen
// can show a "REQUESTS n" count without any push mechanism.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();

try {
    $pdo = silphnet_db();
    $stmt = $pdo->prepare(
        'SELECT a.name, a.trainer_id FROM friends f
         JOIN accounts a ON a.account_id = f.account_id
         WHERE f.friend_id = :me AND f.status = "pending"
         ORDER BY f.created_at ASC'
    );
    $stmt->execute([':me' => $account['account_id']]);
    $rows = $stmt->fetchAll();
    foreach ($rows as &$r) $r['trainer_id'] = str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT);
    silphnet_json(['ok' => true, 'requests' => $rows]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
