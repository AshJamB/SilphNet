<?php
// SilphNet - total count of currently-online players, GLOBALLY (not just
// friends). Uses the exact same ONLINE definition the friends list and
// friend-marker despawn logic already use client-side (main.lua's
// OFFLINE_AFTER, 300 seconds / 5 minutes) so the number on-screen always
// means the same thing everywhere in the mod.
//
// GET: token (still requires a valid session, same as every other
// endpoint - this isn't meant to be a public unauthenticated counter)
// Returns: {"ok":true,"online":12}
//
// One row per (account_id, game_version) in presence, so a single
// account running two saves counts twice - same "character," same
// player, but deliberately not de-duplicated here to match how every
// other presence-derived count in this mod (friends list, markers)
// already treats game_version as its own tracked entity.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

const SILPHNET_ONLINE_AFTER_SECONDS = 300;

silphnet_require_token();   // just needs to be a valid session; doesn't need who

try {
    $pdo = silphnet_db();
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) AS c FROM presence
         WHERE last_seen >= NOW() - INTERVAL ' . SILPHNET_ONLINE_AFTER_SECONDS . ' SECOND'
    );
    $stmt->execute();
    $row = $stmt->fetch();
    silphnet_json(['ok' => true, 'online' => (int)($row['c'] ?? 0)]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
