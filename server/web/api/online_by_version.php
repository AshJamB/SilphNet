<?php
// SilphNet - everyone currently online, GLOBALLY (not just friends),
// grouped by game_version - the data source for the new SN ONLINE
// screen's per-version pages (RED/BLUE/YELLOW), which each list that
// version's online players the same way nearby.php's single flat list
// already does for "who's on my map" (name, trainer_id, add-friend
// status). Replaces online_count.php's single flat number for this
// screen specifically - online_count.php itself is unchanged and still
// used elsewhere (its own single "N PLAYERS ONLINE NOW" figure, if kept
// on a summary line here, would just be sum(counts) over every version
// anyway, so this endpoint alone is enough for the whole screen).
//
// GET: token
// Returns: {"ok":true,"versions":[
//   {"game_version":"RED","count":4,"players":[{"account_id","name","trainer_id"}, ...]},
//   ...
// ]}
//
// Never includes the caller's own account_id or account - same reasoning
// as nearby.php: this is "who ELSE is online", not a mirror. UNKNOWN is
// deliberately excluded entirely (not just a version nobody happens to
// be playing) - a presence row still keyed UNKNOWN means that account's
// client hasn't sent a real game.save.version yet (see ping.php's re-key
// comment), which isn't a genuine "version" a player is playing so much
// as a not-yet-identified one; showing an "UNKNOWN: 2 ONLINE" page would
// be confusing rather than useful. Only RED/BLUE/YELLOW are grouped
// here - GOLD is accepted elsewhere for forward-compatibility but this
// mod is Gen 1 only and no real client sends it today, so an empty GOLD
// group would just be permanent dead weight on this screen.
//
// Versions with zero online players are still included in the "versions"
// array (with an empty "players" array and count 0) rather than omitted -
// the client-side summary page wants to show "RED: 0 ONLINE" rather than
// silently drop a version, so this endpoint always returns exactly three
// entries, in a fixed RED/BLUE/YELLOW order, regardless of how many are
// actually populated.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

const SILPHNET_ONLINE_AFTER_SECONDS = 300;
const SILPHNET_TRACKED_VERSIONS = ['RED', 'BLUE', 'YELLOW'];

$account = silphnet_require_token();

try {
    $pdo = silphnet_db();
    $stmt = $pdo->prepare(
        'SELECT p.game_version, p.account_id, a.name, a.trainer_id
         FROM presence p
         JOIN accounts a ON a.account_id = p.account_id
         WHERE p.game_version IN (' . implode(',', array_fill(0, count(SILPHNET_TRACKED_VERSIONS), '?')) . ')
           AND p.account_id != ?
           AND p.last_seen >= NOW() - INTERVAL ' . SILPHNET_ONLINE_AFTER_SECONDS . ' SECOND
         GROUP BY p.game_version, p.account_id, a.name, a.trainer_id
         ORDER BY a.name ASC'
    );
    // Positional params: the version list first (matching the IN (...)
    // placeholders built above), then the caller's own account_id last.
    // array_merge, not the ...spread operator - spread-inside-an-array-
    // literal needs PHP 7.4+, and this project makes no assumption about
    // the PHP version on whatever shared hosting runs it (every other
    // file here sticks to plain, old-compatible PHP for the same
    // reason - see migrations.sql's "no stored procedures" note).
    $stmt->execute(array_merge(SILPHNET_TRACKED_VERSIONS, [$account['account_id']]));
    $rows = $stmt->fetchAll();

    $byVersion = [];
    foreach (SILPHNET_TRACKED_VERSIONS as $v) $byVersion[$v] = [];
    foreach ($rows as $r) {
        $r['trainer_id'] = str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT);
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
