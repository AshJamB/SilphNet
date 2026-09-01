<?php
// SilphNet - PUBLIC, unauthenticated server-wide totals for the homepage's
// community-stats ticker. Same public-by-design posture as
// public_online_status.php/public_online_players.php/
// public_leaderboards.php - no auth.php, no per-player identity exposed at
// all here (this endpoint returns aggregate numbers only, not even names),
// so it's strictly less sensitive than any of those.
//
// total_pokedex_seen / total_pokedex_caught / total_league_clears /
// total_badges are RAW SUMs across every (account_id, game_version) row in
// friend_stats, server-wide - a running COMMUNITY total, not a
// deduplicated "how many different species has the community caught
// between them" figure. E.g. if two trainers have each caught the same 10
// species, total_pokedex_caught counts that as 20, not 10 - answering "how
// much catching has happened in total" (a bigger, more exciting-looking
// number that only grows), not "how much of the Pokedex does the
// community collectively cover" (a different question that would need a
// UNION-style query per species per game, not a plain SUM, and isn't what
// this ticker is asking).
//
// `versions` also breaks tiles_walked down the same way, alongside the
// other four - added for the homepage's Tiles Walked stat pill, same
// per-version drilldown treatment as the rest (public_stat_by_version.php
// now accepts "tiles_walked" as a stat key too).
//
// `versions` breaks those same four totals down per tracked game version,
// for the homepage's per-stat drilldown modals (Pokemon Seen/Caught,
// Badges, League Victories - same "click to see it split by version" shape
// the players-online pill already has). One GROUP BY query covers every
// tracked version at once, then every tracked version is seeded to 0
// first so a version with zero friend_stats rows still shows up as 0
// rather than being missing from the array entirely - same pattern
// public_online_status.php uses for its own per-version online counts.
// Still no per-player identity anywhere in this response - just per-version
// aggregate totals, same posture as the server-wide totals above.
//
// online_now deliberately duplicates public_online_status.php's own tiny
// "count online" query rather than sharing a helper for it - same
// endpoint-independence reasoning public_online_players.php's own comment
// gives for not sharing logic with online_by_version.php: one file's
// behavior should never change because someone edited a different file.
// A single COUNT(*)-shaped query isn't worth a shared helper in db.php for
// that tradeoff.
//
// total_tiles_walked is the same kind of raw server-wide SUM as the four
// totals above it - added alongside the new tiles-walked leaderboard
// category (tiles_leaderboard.php / SN RECORDS) for the homepage ticker,
// same "bigger number that only grows" framing as total_league_clears.
//
// GET: no params
// Returns: {"ok":true,"total_trainers":N,"online_now":N,
//   "total_pokedex_seen":N,"total_pokedex_caught":N,"total_league_clears":N,
//   "total_badges":N,"total_tiles_walked":N,"versions":[
//     {"game_version":"RED","pokedex_seen":N,"pokedex_caught":N,"badges":N,"league_wins":N},
//     ... one entry per SILPHNET_PUBLIC_TRACKED_VERSIONS entry
//   ]}

require __DIR__ . '/db.php';

const SILPHNET_PUBLIC_ONLINE_AFTER_SECONDS = 300;
const SILPHNET_PUBLIC_TRACKED_VERSIONS = ['RED', 'BLUE', 'YELLOW', 'GOLD', 'SILVER', 'CRYSTAL'];

try {
    $pdo = silphnet_db();

    $stmt = $pdo->query('SELECT COUNT(*) AS c FROM accounts');
    $totalTrainers = (int)$stmt->fetch()['c'];

    $stmt = $pdo->prepare(
        'SELECT COUNT(*) AS c FROM presence
         WHERE game_version IN (' . implode(',', array_fill(0, count(SILPHNET_PUBLIC_TRACKED_VERSIONS), '?')) . ')
           AND last_seen >= NOW() - INTERVAL ' . SILPHNET_PUBLIC_ONLINE_AFTER_SECONDS . ' SECOND'
    );
    $stmt->execute(SILPHNET_PUBLIC_TRACKED_VERSIONS);
    $onlineNow = (int)$stmt->fetch()['c'];

    $stmt = $pdo->query(
        'SELECT
            SUM(pokedex_seen) AS pokedex_seen_total,
            SUM(pokedex_caught) AS pokedex_total,
            SUM(league_wins) AS league_total,
            SUM(badges) AS badges_total,
            SUM(tiles_walked) AS tiles_walked_total
         FROM friend_stats'
    );
    $row = $stmt->fetch();

    $stmt = $pdo->prepare(
        'SELECT
            game_version,
            SUM(pokedex_seen) AS pokedex_seen_total,
            SUM(pokedex_caught) AS pokedex_caught_total,
            SUM(badges) AS badges_total,
            SUM(league_wins) AS league_wins_total,
            SUM(tiles_walked) AS tiles_walked_total
         FROM friend_stats
         WHERE game_version IN (' . implode(',', array_fill(0, count(SILPHNET_PUBLIC_TRACKED_VERSIONS), '?')) . ')
         GROUP BY game_version'
    );
    $stmt->execute(SILPHNET_PUBLIC_TRACKED_VERSIONS);
    $versionRows = $stmt->fetchAll();

    $versionTotals = [];
    foreach (SILPHNET_PUBLIC_TRACKED_VERSIONS as $v) {
        $versionTotals[$v] = ['pokedex_seen' => 0, 'pokedex_caught' => 0, 'badges' => 0, 'league_wins' => 0, 'tiles_walked' => 0];
    }
    foreach ($versionRows as $r) {
        $versionTotals[$r['game_version']] = [
            'pokedex_seen' => (int)($r['pokedex_seen_total'] ?? 0),
            'pokedex_caught' => (int)($r['pokedex_caught_total'] ?? 0),
            'badges' => (int)($r['badges_total'] ?? 0),
            'league_wins' => (int)($r['league_wins_total'] ?? 0),
            'tiles_walked' => (int)($r['tiles_walked_total'] ?? 0),
        ];
    }

    $versions = [];
    foreach (SILPHNET_PUBLIC_TRACKED_VERSIONS as $v) {
        $versions[] = array_merge(['game_version' => $v], $versionTotals[$v]);
    }

    silphnet_json([
        'ok' => true,
        'total_trainers' => $totalTrainers,
        'online_now' => $onlineNow,
        'total_pokedex_seen' => (int)($row['pokedex_seen_total'] ?? 0),
        'total_pokedex_caught' => (int)($row['pokedex_total'] ?? 0),
        'total_league_clears' => (int)($row['league_total'] ?? 0),
        'total_badges' => (int)($row['badges_total'] ?? 0),
        'total_tiles_walked' => (int)($row['tiles_walked_total'] ?? 0),
        'versions' => $versions,
    ]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
