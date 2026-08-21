<?php
// SilphNet - everyone currently online, GLOBALLY (not just friends),
// grouped by game_version - the data source for the new SN ONLINE
// screen's per-version pages (RED/BLUE/YELLOW/GOLD/SILVER), which each
// list that version's online players the same way nearby.php's single
// flat list already does for "who's on my map" (name, trainer_id,
// add-friend status). Replaces online_count.php's single flat number for
// this screen specifically - online_count.php itself is unchanged and
// still used elsewhere (its own single "N PLAYERS ONLINE NOW" figure, if
// kept on a summary line here, would just be sum(counts) over every
// version anyway, so this endpoint alone is enough for the whole screen).
//
// GET: token
// Returns: {"ok":true,"versions":[
//   {"game_version":"RED","count":4,"players":[{"account_id","name","trainer_id","is_you"}, ...]},
//   ...
// ]}
//
// DOES include the caller, both in each version's count and in that
// version's players array (as their own entry, flagged "is_you":true) -
// this screen is meant to answer "how many people total are playing
// right now, including me", unlike nearby.php's "who ELSE is on my map"
// (which stays caller-excluded, since a marker for yourself on your own
// map would be meaningless). The mod's own SilphNetOnline screen is
// responsible for using is_you to skip the add-friend prompt on the
// caller's own row - this endpoint just tells the truth about who's
// online and lets the client decide what to do with that.
//
// UNKNOWN is deliberately excluded entirely (not just a version nobody
// happens to be playing) - a presence row still keyed UNKNOWN means that
// account's client hasn't sent a real game.save.version yet (see
// ping.php's re-key comment), which isn't a genuine "version" a player is
// playing so much as a not-yet-identified one; showing an "UNKNOWN: 2
// ONLINE" page would be confusing rather than useful. RED/BLUE/YELLOW
// (Gen 1) and now GOLD/SILVER (Gen 2, Beta) are all grouped here -
// main.lua sends GOLD/SILVER as a real game_version as of the version
// that added Gen 2 support, not just forward-compatibly accepted and
// unused.
//
// Versions with zero online players are still included in the "versions"
// array (with an empty "players" array and count 0) rather than omitted -
// the client-side summary page wants to show "RED: 0 ONLINE" rather than
// silently drop a version, so this endpoint always returns exactly five
// entries, in a fixed RED/BLUE/YELLOW/GOLD/SILVER order, regardless of how
// many are actually populated.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

const SILPHNET_ONLINE_AFTER_SECONDS = 300;
const SILPHNET_TRACKED_VERSIONS = ['RED', 'BLUE', 'YELLOW', 'GOLD', 'SILVER'];

$account = silphnet_require_token();

try {
    $pdo = silphnet_db();
    // No "AND p.account_id != ?" here - the caller is deliberately
    // included (see the file comment above for why this differs from
    // nearby.php).
    $stmt = $pdo->prepare(
        'SELECT p.game_version, p.account_id, a.name, a.trainer_id
         FROM presence p
         JOIN accounts a ON a.account_id = p.account_id
         WHERE p.game_version IN (' . implode(',', array_fill(0, count(SILPHNET_TRACKED_VERSIONS), '?')) . ')
           AND p.last_seen >= NOW() - INTERVAL ' . SILPHNET_ONLINE_AFTER_SECONDS . ' SECOND
         GROUP BY p.game_version, p.account_id, a.name, a.trainer_id
         ORDER BY a.name ASC'
    );
    $stmt->execute(SILPHNET_TRACKED_VERSIONS);
    $rows = $stmt->fetchAll();

    $byVersion = [];
    foreach (SILPHNET_TRACKED_VERSIONS as $v) $byVersion[$v] = [];
    foreach ($rows as $r) {
        $r['trainer_id'] = str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT);
        $r['is_you'] = ($r['account_id'] === $account['account_id']);
        $gv = $r['game_version'];
        unset($r['game_version']);
        $byVersion[$gv][] = $r;
    }

    $versions = [];
    foreach (SILPHNET_TRACKED_VERSIONS as $v) {
        $versions[] = ['game_version' => $v, 'count' => count($byVersion[$v]), 'players' => $byVersion[$v]];
    }

    silphnet_json(['ok' => true, 'versions' => $versions]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
