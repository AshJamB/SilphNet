<?php
// SilphNet - Pokedex completion leaderboard, a third category on the same
// "SN RECORDS" sign the league leaderboard already lives on (see
// main.lua). Reuses the same physical sign rather than adding a separate
// NPC to place, per direct request.
//
// Ranked by BEST SINGLE-VERSION completion percentage, deliberately NOT
// summed across saves the way league_leaderboard.php/tiles_leaderboard.php
// both are - catching the same Pikachu on a Red save and again on a Gold
// save doesn't add up to some combined dex any more than it would on a
// real cartridge; each save has its own separate Pokedex. "Best" means
// whichever single save this account has made the most progress on is the
// number that represents them here.
//
// Gen 1 (Red/Blue/Yellow) and Gen 2 (Gold/Silver/Crystal) have different
// real dex sizes - 151 (Kanto) vs 251 (Kanto+Johto combined, as of this
// era of the games) - so a save's game_version decides which total its
// own percentage is computed against. Computed in PHP rather than SQL
// (see the two MAX(CASE...) columns below) specifically to avoid needing
// window functions/correlated subqueries just to find "the row with this
// account's best percentage" - this shared hosting's MySQL version isn't
// assumed to support those, and a plain GROUP BY/MAX per generation stays
// portable everywhere plain ALTER TABLE already works.
//
// GET: token
// Returns: {"ok":true,
//   "all":[{"account_id","name","trainer_id","pct"}, ...],     (top 50)
//   "friends":[{"account_id","name","trainer_id","pct"}, ...]} (accepted friends only)
//
// pct is a plain 0-100 integer (rounded), not a fraction - main.lua draws
// it directly as "<pct>%" with no further math needed.
//
// Accounts with a best percentage of 0 (never caught anything on any
// save) are excluded from both lists, same reasoning as the other two
// leaderboards on this sign.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

const SILPHNET_DEX_LEADERBOARD_ALL_LIMIT = 50;
const SILPHNET_GEN1_DEX_TOTAL = 151;
const SILPHNET_GEN2_DEX_TOTAL = 251;

$account = silphnet_require_token();

// Turns { gen1_caught, gen2_caught } (either may be null - no save of that
// generation exists yet for this account) into a single best 0-100 int.
function silphnet_best_dex_pct($gen1Caught, $gen2Caught) {
    $gen1Pct = $gen1Caught !== null ? ((int)$gen1Caught / SILPHNET_GEN1_DEX_TOTAL) * 100 : 0;
    $gen2Pct = $gen2Caught !== null ? ((int)$gen2Caught / SILPHNET_GEN2_DEX_TOTAL) * 100 : 0;
    $best = max($gen1Pct, $gen2Pct);
    if ($best > 100) $best = 100;   // defensive - a caught count somehow above the real dex size shouldn't show over 100%
    return (int)round($best);
}

try {
    $pdo = silphnet_db();

    $stmt = $pdo->prepare(
        "SELECT a.account_id, a.name, a.trainer_id,
                MAX(CASE WHEN fs.game_version IN ('GOLD','SILVER','CRYSTAL') THEN NULL ELSE fs.pokedex_caught END) AS gen1_caught,
                MAX(CASE WHEN fs.game_version IN ('GOLD','SILVER','CRYSTAL') THEN fs.pokedex_caught ELSE NULL END) AS gen2_caught
         FROM friend_stats fs
         JOIN accounts a ON a.account_id = fs.account_id
         GROUP BY a.account_id, a.name, a.trainer_id"
    );
    $stmt->execute();
    $all = [];
    foreach ($stmt->fetchAll() as $r) {
        $pct = silphnet_best_dex_pct($r['gen1_caught'], $r['gen2_caught']);
        if ($pct <= 0) continue;
        $all[] = ['account_id' => $r['account_id'], 'name' => $r['name'],
                   'trainer_id' => str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT), 'pct' => $pct];
    }
    usort($all, function ($x, $y) { return $y['pct'] - $x['pct']; });
    $all = array_slice($all, 0, SILPHNET_DEX_LEADERBOARD_ALL_LIMIT);

    $stmt = $pdo->prepare(
        "SELECT a.account_id, a.name, a.trainer_id,
                MAX(CASE WHEN fs.game_version IN ('GOLD','SILVER','CRYSTAL') THEN NULL ELSE fs.pokedex_caught END) AS gen1_caught,
                MAX(CASE WHEN fs.game_version IN ('GOLD','SILVER','CRYSTAL') THEN fs.pokedex_caught ELSE NULL END) AS gen2_caught
         FROM friends f
         JOIN accounts a ON a.account_id = f.friend_id
         JOIN friend_stats fs ON fs.account_id = f.friend_id
         WHERE f.account_id = :account_id AND f.status = 'accepted'
         GROUP BY a.account_id, a.name, a.trainer_id"
    );
    $stmt->execute([':account_id' => $account['account_id']]);
    $friends = [];
    foreach ($stmt->fetchAll() as $r) {
        $pct = silphnet_best_dex_pct($r['gen1_caught'], $r['gen2_caught']);
        if ($pct <= 0) continue;
        $friends[] = ['account_id' => $r['account_id'], 'name' => $r['name'],
                       'trainer_id' => str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT), 'pct' => $pct];
    }
    usort($friends, function ($x, $y) { return $y['pct'] - $x['pct']; });

    silphnet_json(['ok' => true, 'all' => $all, 'friends' => $friends]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
