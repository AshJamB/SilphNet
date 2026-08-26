<?php
// SilphNet - PUBLIC, unauthenticated per-player breakdown of ONE stat on
// ONE specific game version - the second-level drilldown when a visitor
// clicks a version row inside one of the homepage's stat modals (Pokemon
// Seen/Caught, Badges, League Victories). Same idea as
// public_online_players.php's own version->player-list drilldown for the
// "players online" pill, and deliberately built the same way: the
// summary level (public_community_stats.php's per-version TOTALS) stays
// its own cheap, already-cached response, and this identity-bearing
// per-player detail is only ever fetched on demand, the moment a visitor
// actually clicks into one specific version - never pre-loaded for every
// version up front.
//
// Unlike public_leaderboards.php (which ranks a person by their COMBINED
// total across every game_version they've played), this ranks by that
// person's value FOR THIS ONE VERSION ONLY - "who has caught the most in
// RED specifically", not "who has caught the most overall". A player
// with a huge combined total but 0 in this particular version is
// correctly absent from this list, not just ranked last.
//
// GET: stat=pokedex_seen|pokedex_caught|badges|league_wins,
//      game_version=RED|BLUE|YELLOW|GOLD|SILVER|CRYSTAL
// Returns: {"ok":true,"stat":"pokedex_caught","game_version":"RED",
//   "players":[{"name","trainer_id","total"}, ...]}   (top 50, ranked
//   DESC on that one version's own value, 0 totals excluded, ties broken
//   alphabetically by name - same convention public_leaderboards.php
//   uses and for the same reason: a stable, visibly-explainable order
//   rather than one that depends on row-insert order or account_id.)
//
// $stat is validated against a fixed whitelist before ever reaching SQL -
// PDO can only parameterize VALUES, not column names, so the column name
// itself is chosen from SILPHNET_STAT_COLUMNS by exact match rather than
// ever being interpolated from raw user input.

require __DIR__ . '/db.php';

const SILPHNET_PUBLIC_TRACKED_VERSIONS = ['RED', 'BLUE', 'YELLOW', 'GOLD', 'SILVER', 'CRYSTAL'];
const SILPHNET_STAT_COLUMNS = ['pokedex_seen', 'pokedex_caught', 'badges', 'league_wins'];
const SILPHNET_STAT_BY_VERSION_LIMIT = 50;

$version = strtoupper(trim($_GET['game_version'] ?? ''));
if (!in_array($version, SILPHNET_PUBLIC_TRACKED_VERSIONS, true)) {
    silphnet_error('game_version must be one of RED, BLUE, YELLOW, GOLD, SILVER, CRYSTAL');
}

$stat = strtolower(trim($_GET['stat'] ?? ''));
if (!in_array($stat, SILPHNET_STAT_COLUMNS, true)) {
    silphnet_error('stat must be one of pokedex_seen, pokedex_caught, badges, league_wins');
}

try {
    $pdo = silphnet_db();
    // $stat is safe to splice directly into the column position here -
    // it was just checked against SILPHNET_STAT_COLUMNS above with strict
    // in_array, so it can only ever be one of those four literal strings,
    // never arbitrary input.
    $stmt = $pdo->prepare(
        "SELECT a.name, a.trainer_id, fs.$stat AS total
         FROM friend_stats fs
         JOIN accounts a ON a.account_id = fs.account_id
         WHERE fs.game_version = :version AND fs.$stat > 0
         ORDER BY total DESC, a.name ASC
         LIMIT " . SILPHNET_STAT_BY_VERSION_LIMIT
    );
    $stmt->execute([':version' => $version]);
    $rows = $stmt->fetchAll();
    foreach ($rows as &$r) {
        $r['trainer_id'] = str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT);
        $r['total'] = (int)$r['total'];
    }
    unset($r);

    silphnet_json(['ok' => true, 'stat' => $stat, 'game_version' => $version, 'players' => $rows]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
