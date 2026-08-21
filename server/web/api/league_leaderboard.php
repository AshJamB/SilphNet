<?php
// SilphNet - league-clear leaderboard for the sign near the Elite Four
// entrance (INDIGO_PLATEAU_LOBBY in Gen1; the mod registers this hook
// unconditionally and no-ops via pcall if that map id doesn't exist at
// runtime for a given generation, so this endpoint has no idea - and
// doesn't need to care - which game a given caller is actually in).
//
// "Total league clears" is SUM(league_wins) across every game_version row
// an account has in friend_stats - one combined number per PERSON, not
// per save, since a trainer who cleared the league on both RED and
// YELLOW should show one bigger number, not two separate smaller
// entries. This deliberately differs from friends.php/friend_detail.php,
// which are both scoped per (account, game_version) - the leaderboard is
// the one place in this project where "collapse across saves" is the
// right answer, because the sign's whole point is bragging rights for a
// person, not a distinction between which cartridge they used.
//
// GET: token
// Returns: {"ok":true,
//   "all":[{"account_id","name","trainer_id","total"}, ...],     (top 50)
//   "friends":[{"account_id","name","trainer_id","total"}, ...]} (accepted friends only)
//
// Both lists are ordered total DESC (highest first) - ascending vs
// descending is purely a client-side toggle (main.lua already has the
// full list in memory once fetched, so it just reverses the array
// in-place rather than this endpoint needing a second round trip for the
// opposite order).
//
// Accounts with a total of 0 are excluded from BOTH lists - there's no
// value in a leaderboard sign listing every registered player who has
// never once cleared the league, and it would make the "all" list
// unboundedly long as the player base grows instead of meaningfully
// ranked.
//
// "friends" is restricted to the caller's ACCEPTED friends only (not
// including the caller themselves) - deliberately distinct from the
// "all" list rather than "all players including me", matching how the
// SN FRIENDS list elsewhere in this project is always a distinct set
// from SN ONLINE's global list.
//
// No free-text of any kind is ever returned here - every field is either
// a server-known display name (already validated at account-creation
// time elsewhere in this project), a zero-padded numeric trainer id, or
// a plain integer total. This endpoint cannot be used to relay arbitrary
// player-authored text between clients.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

const SILPHNET_LEADERBOARD_ALL_LIMIT = 50;

$account = silphnet_require_token();

try {
    $pdo = silphnet_db();

    // "all" - top scorers across every account with a nonzero combined
    // total, regardless of friendship. HAVING (not WHERE) since the
    // exclusion is on the aggregated SUM, not a raw column.
    $stmt = $pdo->prepare(
        'SELECT a.account_id, a.name, a.trainer_id, SUM(fs.league_wins) AS total
         FROM friend_stats fs
         JOIN accounts a ON a.account_id = fs.account_id
         GROUP BY a.account_id, a.name, a.trainer_id
         HAVING total > 0
         ORDER BY total DESC
         LIMIT ' . SILPHNET_LEADERBOARD_ALL_LIMIT
    );
    $stmt->execute();
    $all = $stmt->fetchAll();
    foreach ($all as &$r) {
        $r['trainer_id'] = str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT);
        $r['total'] = (int)$r['total'];
    }
    unset($r);

    // "friends" - same aggregation, restricted to the caller's accepted
    // friends via the same friends-table JOIN pattern friends.php already
    // uses elsewhere in this project. Deliberately excludes the caller's
    // own total (see file comment above) and has no LIMIT, since a
    // friends list is already bounded by however many friends someone
    // has accepted.
    $stmt = $pdo->prepare(
        'SELECT a.account_id, a.name, a.trainer_id, SUM(fs.league_wins) AS total
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
