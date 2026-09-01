<?php
// SilphNet - tiles-walked leaderboard, a second category on the same "SN
// RECORDS" sign the league leaderboard already lives on (see main.lua -
// this reuses the exact same physical sign/screen rather than adding a
// separate NPC to place, per direct request to avoid tripling the sign-
// placement risk already documented on the league sign).
//
// "Total tiles walked" is SUM(tiles_walked) across every game_version row
// an account has in friend_stats - same "collapse across saves" reasoning
// as league_leaderboard.php: this is bragging rights for a PERSON, not a
// distinction between which cartridge they walked around on.
//
// GET: token
// Returns: {"ok":true,
//   "all":[{"account_id","name","trainer_id","total"}, ...],     (top 50)
//   "friends":[{"account_id","name","trainer_id","total"}, ...]} (accepted friends only)
//
// Deliberately the SAME row shape ("total") as league_leaderboard.php's
// response - main.lua's parseLeagueLeaderboardJson and myLeagueClears-style
// own-total lookup are both generic enough to be reused as-is for this
// endpoint too, rather than needing their own parallel copies.
//
// Accounts with a total of 0 are excluded from both lists, same reasoning
// as league_leaderboard.php - no value in listing every registered player
// who has never taken a single step.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

const SILPHNET_TILES_LEADERBOARD_ALL_LIMIT = 50;

$account = silphnet_require_token();

try {
    $pdo = silphnet_db();

    $stmt = $pdo->prepare(
        'SELECT a.account_id, a.name, a.trainer_id, SUM(fs.tiles_walked) AS total
         FROM friend_stats fs
         JOIN accounts a ON a.account_id = fs.account_id
         GROUP BY a.account_id, a.name, a.trainer_id
         HAVING total > 0
         ORDER BY total DESC
         LIMIT ' . SILPHNET_TILES_LEADERBOARD_ALL_LIMIT
    );
    $stmt->execute();
    $all = $stmt->fetchAll();
    foreach ($all as &$r) {
        $r['trainer_id'] = str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT);
        $r['total'] = (int)$r['total'];
    }
    unset($r);

    $stmt = $pdo->prepare(
        'SELECT a.account_id, a.name, a.trainer_id, SUM(fs.tiles_walked) AS total
         FROM friends f
         JOIN accounts a ON a.account_id = f.friend_id
         JOIN friend_stats fs ON fs.account_id = f.friend_id
         WHERE f.account_id = :account_id AND f.status = "accepted"
         GROUP BY a.account_id, a.name, a.trainer_id
         HAVING total > 0
         ORDER BY total DESC'
    );
    $stmt->execute([':account_id' => $account['account_id']]);
    $friends = $stmt->fetchAll();
    foreach ($friends as &$r) {
        $r['trainer_id'] = str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT);
        $r['total'] = (int)$r['total'];
    }
    unset($r);

    silphnet_json(['ok' => true, 'all' => $all, 'friends' => $friends]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
