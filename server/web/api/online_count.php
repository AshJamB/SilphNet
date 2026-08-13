<?php
// SilphNet - total count of currently-online players, GLOBALLY (everyone,
// not just friends, INCLUDING the caller). Uses the exact same ONLINE
// definition the friends list and friend-marker despawn logic already use
// client-side (main.lua's OFFLINE_AFTER, 300 seconds / 5 minutes) so the
// number on-screen always means the same thing everywhere in the mod.
//
// GET: token (still requires a valid session, same as every other
// endpoint - this isn't meant to be a public unauthenticated counter)
// Returns: {"ok":true,"online":12}
//
// This briefly excluded the caller's own account (see git history) when
// it was shown on the status screen's A:FRIENDS hint line - reported
// directly as confusing, since a player with zero friends online but
// who was themselves within the 5-minute window saw "(1 ON)" right next
// to a friends list showing everyone OFFLINE, easy to misread as "one of
// my friends is online". The actual fix was to stop showing this GLOBAL
// number on the friends-focused hint at all, not to change what this
// number means - the status screen's A:FRIENDS hint now shows a
// friends-only online count instead (computed client-side from the
// existing friends list, no separate endpoint), and this global
// (self-inclusive) count moved to its own "SN ONLINE" Start Menu
// row/screen, well away from anything friends-related, so there's no
// longer a place where these two different numbers could be confused
// for one another.
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
