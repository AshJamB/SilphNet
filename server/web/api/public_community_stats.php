<?php
// SilphNet - PUBLIC, unauthenticated server-wide totals for the homepage's
// community-stats ticker. Same public-by-design posture as
// public_online_status.php/public_online_players.php/
// public_leaderboards.php - no auth.php, no per-player identity exposed at
// all here (this endpoint returns aggregate numbers only, not even names),
// so it's strictly less sensitive than any of those.
//
// total_pokedex_caught / total_league_clears / total_badges are RAW SUMs
// across every (account_id, game_version) row in friend_stats, server-wide -
// a running COMMUNITY total, not a deduplicated "how many different species
// has the community caught between them" figure. E.g. if two trainers have
// each caught the same 10 species, total_pokedex_caught counts that as 20,
// not 10 - answering "how much catching has happened in total" (a bigger,
// more exciting-looking number that only grows), not "how much of the
// Pokedex does the community collectively cover" (a different question
// that would need a UNION-style query per species per game, not a plain
// SUM, and isn't what this ticker is asking).
//
// online_now deliberately duplicates public_online_status.php's own tiny
// "count online" query rather than sharing a helper for it - same
// endpoint-independence reasoning public_online_players.php's own comment
// gives for not sharing logic with online_by_version.php: one file's
// behavior should never change because someone edited a different file.
// A single COUNT(*)-shaped query isn't worth a shared helper in db.php for
// that tradeoff.
//
// GET: no params
// Returns: {"ok":true,"total_trainers":N,"online_now":N,
//   "total_pokedex_caught":N,"total_league_clears":N,"total_badges":N}

require __DIR__ . '/db.php';

const SILPHNET_PUBLIC_ONLINE_AFTER_SECONDS = 300;
const SILPHNET_PUBLIC_TRACKED_VERSIONS = ['RED', 'BLUE', 'YELLOW', 'GOLD', 'SILVER'];

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
            SUM(pokedex_caught) AS pokedex_total,
            SUM(league_wins) AS league_total,
            SUM(badges) AS badges_total
         FROM friend_stats'
    );
    $row = $stmt->fetch();

    silphnet_json([
        'ok' => true,
        'total_trainers' => $totalTrainers,
        'online_now' => $onlineNow,
        'total_pokedex_caught' => (int)($row['pokedex_total'] ?? 0),
        'total_league_clears' => (int)($row['league_total'] ?? 0),
        'total_badges' => (int)($row['badges_total'] ?? 0),
    ]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
