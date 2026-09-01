<?php
// SilphNet - PUBLIC, unauthenticated combined leaderboards for the website
// homepage's "LEADERBOARDS" section (League Clears / Badges / Pokedex
// Caught tabs). Deliberately a SEPARATE endpoint from the in-game
// league_leaderboard.php rather than reusing it - that one requires a
// session token and returns a "friends" list scoped to the caller's own
// accepted friends, neither of which makes sense here: a website visitor
// isn't logged into any SilphNet account at all, so there's no token to
// send and no "friends of the caller" concept to restrict a second list
// to. This endpoint only ever returns the "everyone" shape, for all three
// stats instead of just league_wins, and needs no auth.php at all - same
// public-by-design posture as public_online_status.php/
// public_online_players.php (names + Trainer IDs are already fine to show
// with no login, per that established decision - see those files' own
// comments).
//
// "Total" for every stat is SUM(...) across every game_version row an
// account has in friend_stats - one combined number per PERSON, not per
// save, identical in spirit to league_leaderboard.php's own "all" list
// (see that file's comment for why "collapse across saves" is the right
// call for a leaderboard specifically, unlike friends.php/friend_detail.php
// which stay scoped per (account, game_version)).
//
// All three totals (league_wins, badges, pokedex_caught) are fetched in
// ONE query per account rather than three independent queries, because the
// "title" pill shown next to a name has to be computed from that SAME
// person's totals across ALL three stats together (see SILPHNET_TITLE_TIERS
// below) - running the league list's title off one query and the badges
// list's title off a differently-filtered query for the same account could
// disagree with each other if a row changed between queries. One query,
// one consistent snapshot, three derived+filtered/sorted/limited views of
// it in PHP.
//
// GET: no params
// Returns: {"ok":true,
//   "league":[{"name","trainer_id","total","title"}, ...],   (top 50, ranked by league_wins)
//   "badges":[{"name","trainer_id","total","title"}, ...],   (top 50, ranked by badges)
//   "pokedex":[{"name","trainer_id","total","title"}, ...],  (top 50, ranked by pokedex_caught)
//   "seen":[{"name","trainer_id","total","title"}, ...],     (top 50, ranked by pokedex_seen)
//   "tiles":[{"name","trainer_id","total","title"}, ...],    (top 50, ranked by tiles_walked)
//   "dex_pct":[{"name","trainer_id","total","title"}, ...]}  (top 50, ranked by best single-save dex %)
//
// tiles mirrors league/badges/pokedex/seen exactly - SUM(tiles_walked)
// across every game_version row an account has, same "one combined
// number per PERSON" reasoning (see comment above), matching how the
// in-game SN RECORDS sign's tiles-walked category is also summed
// (tiles_leaderboard.php).
//
// dex_pct is the one list here that does NOT sum across saves - it's the
// same BEST SINGLE-SAVE completion percentage the in-game SN RECORDS
// sign's Pokedex category uses (dex_leaderboard.php), for the identical
// reason: catching a species on two different saves isn't double
// Pokedex progress. "total" for this list is a plain 0-100 integer
// percentage, not a count - the website renders it with a trailing "%"
// rather than as a bare number (see index.php's renderLeaderboardTab).
//
// Each list independently excludes accounts with a 0 total in the stat
// THAT list is ranked by (same HAVING-style exclusion league_leaderboard.php
// uses) - an account with 40 badges but 0 league clears still belongs on
// the badges list, just not the league one.
//
// Ties (e.g. two accounts both sitting at a version's real max - all 8
// Kanto badges - where the raw total genuinely can't separate them any
// further) break alphabetically by name, ascending - a stable, obvious
// tiebreak a visitor can understand at a glance ("why is X above Y - oh,
// alphabetical") rather than an arbitrary one that depends on row-insert
// order or account_id, which would look unstable/unfair for no visible
// reason.

require __DIR__ . '/db.php';

const SILPHNET_PUBLIC_LEADERBOARD_LIMIT = 50;
const SILPHNET_GEN1_DEX_TOTAL = 151;
const SILPHNET_GEN2_DEX_TOTAL = 251;

// Same helper as dex_leaderboard.php - turns { gen1_caught, gen2_caught }
// (either may be null - no save of that generation exists yet for this
// account) into a single best 0-100 int. Kept as its own local copy
// rather than shared/required from dex_leaderboard.php, matching this
// project's existing convention of small self-contained API endpoints
// with no shared PHP modules beyond db.php/auth.php.
function silphnet_best_dex_pct($gen1Caught, $gen2Caught) {
    $gen1Pct = $gen1Caught !== null ? ((int)$gen1Caught / SILPHNET_GEN1_DEX_TOTAL) * 100 : 0;
    $gen2Pct = $gen2Caught !== null ? ((int)$gen2Caught / SILPHNET_GEN2_DEX_TOTAL) * 100 : 0;
    $best = max($gen1Pct, $gen2Pct);
    if ($best > 100) $best = 100;
    return (int)round($best);
}

// Priority-ordered tier list - first match wins, evaluated top to bottom
// against one account's own combined totals. Deliberately NOT a simple
// "highest total wins" scheme across stats - a "SilphNet Legend"/"Champion"
// title is meant to outrank a "Gym Crusher"/"Pokemon Collector" one
// regardless of the exact numbers involved, since clearing the league at
// all is a rarer, harder-to-fake achievement than accumulating badges or
// catches over time.
function silphnet_public_title($leagueWins, $badges, $pokedexCaught) {
    if ($leagueWins >= 5) return 'SilphNet Legend';
    if ($leagueWins >= 1) return 'Champion';
    if ($badges >= 8) return 'Gym Crusher';
    if ($pokedexCaught >= 50) return 'Pokemon Collector';
    return 'Trainer';
}

try {
    $pdo = silphnet_db();

    // One row per account, combined across every game_version they have a
    // friend_stats row for - no HAVING here, since a given account might be
    // 0 in one stat and nonzero in another; the per-list filtering happens
    // in PHP below once every account's three totals are known together.
    $stmt = $pdo->prepare(
        'SELECT a.name, a.trainer_id,
                SUM(fs.league_wins) AS league_total,
                SUM(fs.badges) AS badges_total,
                SUM(fs.pokedex_caught) AS pokedex_total,
                SUM(fs.pokedex_seen) AS seen_total,
                SUM(fs.tiles_walked) AS tiles_total,
                MAX(CASE WHEN fs.game_version IN ("GOLD","SILVER","CRYSTAL") THEN NULL ELSE fs.pokedex_caught END) AS gen1_caught,
                MAX(CASE WHEN fs.game_version IN ("GOLD","SILVER","CRYSTAL") THEN fs.pokedex_caught ELSE NULL END) AS gen2_caught
         FROM friend_stats fs
         JOIN accounts a ON a.account_id = fs.account_id
         GROUP BY a.account_id, a.name, a.trainer_id'
    );
    $stmt->execute();
    $rows = $stmt->fetchAll();

    $players = [];
    foreach ($rows as $r) {
        $leagueTotal = (int)$r['league_total'];
        $badgesTotal = (int)$r['badges_total'];
        $pokedexTotal = (int)$r['pokedex_total'];
        $seenTotal = (int)$r['seen_total'];
        $tilesTotal = (int)$r['tiles_total'];
        $dexPct = silphnet_best_dex_pct($r['gen1_caught'], $r['gen2_caught']);
        $players[] = [
            'name' => $r['name'],
            'trainer_id' => str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT),
            'league_total' => $leagueTotal,
            'badges_total' => $badgesTotal,
            'pokedex_total' => $pokedexTotal,
            'seen_total' => $seenTotal,
            'tiles_total' => $tilesTotal,
            'dex_pct_total' => $dexPct,
            'title' => silphnet_public_title($leagueTotal, $badgesTotal, $pokedexTotal),
        ];
    }

    // Builds one ranked/filtered/limited public-facing list (name,
    // trainer_id, total, title) for a given stat key, sorted by that
    // stat's total DESC then name ASC (see the tiebreak comment above),
    // excluding zero totals - same "0 isn't worth ranking" rule
    // league_leaderboard.php's "all" list already applies.
    $buildList = function ($totalKey) use ($players) {
        $filtered = array_values(array_filter($players, function ($p) use ($totalKey) {
            return $p[$totalKey] > 0;
        }));
        usort($filtered, function ($a, $b) use ($totalKey) {
            $byTotal = $b[$totalKey] <=> $a[$totalKey];
            if ($byTotal !== 0) return $byTotal;
            return strcasecmp($a['name'], $b['name']);
        });
        $filtered = array_slice($filtered, 0, SILPHNET_PUBLIC_LEADERBOARD_LIMIT);
        return array_map(function ($p) use ($totalKey) {
            return [
                'name' => $p['name'],
                'trainer_id' => $p['trainer_id'],
                'total' => $p[$totalKey],
                'title' => $p['title'],
            ];
        }, $filtered);
    };

    silphnet_json([
        'ok' => true,
        'league' => $buildList('league_total'),
        'badges' => $buildList('badges_total'),
        'pokedex' => $buildList('pokedex_total'),
        'seen' => $buildList('seen_total'),
        'tiles' => $buildList('tiles_total'),
        'dex_pct' => $buildList('dex_pct_total'),
    ]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
