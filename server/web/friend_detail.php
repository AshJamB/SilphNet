<?php
// SilphNet - stats + activity + last-known-position for ONE friend, for
// the in-game friend detail screen (SilphNetFriendDetail, pushed via A on
// a friend in the friends list). Deliberately a separate endpoint from
// friends.php rather than folding this into that list response - the
// list screen only ever needs name/map/tile/time-ago for EVERY friend on
// every page flip, but the detail screen only needs the full stats
// breakdown for the ONE friend currently being viewed, on demand.
//
// POST: token, account_id
// Returns: {"ok":true,
//           "versions":[{"game_version","stats":{...}|null,
//                         "activity":{"message","created_at"}|null}, ...],
//           "presence":{"map_id","x","y","facing","last_seen","game_version"}|null}
//
// Returns ALL of this friend's versions in ONE response, not one version
// per request - the friend detail screen cycles STATS/ACTIVITY across
// every version on a single button (A), so it needs the full set upfront
// to build that cycle rather than firing a fresh network round-trip on
// every single button press. "versions" only ever includes a version if
// it has stats OR activity - a version with presence pings but no
// self-reported stats yet (e.g. a friend who just started a new file)
// is deliberately left out of this list entirely, per direct feedback
// ("don't show those screens if they haven't registered those game
// versions") - presence alone isn't "registering" a version for this
// screen's purposes, only an actual stats/activity upload is.
//
// "presence" is returned separately, just the single MOST RECENT ping
// across all of this friend's versions (not per-version) - last-seen on
// this screen mirrors what the main friends list already shows for
// whichever entry got you here, it isn't part of the per-version cycle.
//
// Only returns data for an ACCEPTED friend of the caller - same
// friendship check every other friend-scoped endpoint in this project
// already does, so this can't be used to pull a stranger's stats by
// guessing their account_id.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();

$friendId = trim($_POST['account_id'] ?? '');
if ($friendId === '') silphnet_error('missing required field: account_id');
$friendId = substr($friendId, 0, 16);

try {
    $pdo = silphnet_db();

    $stmt = $pdo->prepare(
        'SELECT 1 FROM friends WHERE account_id = :me AND friend_id = :friend_id AND status = "accepted"'
    );
    $stmt->execute([':me' => $account['account_id'], ':friend_id' => $friendId]);
    if (!$stmt->fetch()) silphnet_error('not an accepted friend', 403);

    $stmt = $pdo->prepare(
        'SELECT game_version, badges, pokedex_seen, pokedex_caught, league_wins, money, play_seconds, party, updated_at
         FROM friend_stats WHERE account_id = :friend_id'
    );
    $stmt->execute([':friend_id' => $friendId]);
    $statsByVersion = [];
    foreach ($stmt->fetchAll() as $row) {
        $v = $row['game_version'];
        unset($row['game_version']);
        $statsByVersion[$v] = $row;
    }

    $stmt = $pdo->prepare(
        'SELECT game_version, message, created_at FROM friend_activity WHERE account_id = :friend_id'
    );
    $stmt->execute([':friend_id' => $friendId]);
    $activityByVersion = [];
    foreach ($stmt->fetchAll() as $row) {
        $v = $row['game_version'];
        unset($row['game_version']);
        $activityByVersion[$v] = $row;
    }

    // Union of versions that have EITHER stats or activity - a version
    // with only one of the two still gets a slot (its other page just
    // shows NO STATS YET / NO ACTIVITY YET, same as today), but a
    // version with NEITHER (presence-only) is excluded entirely.
    $versionSet = array_unique(array_merge(array_keys($statsByVersion), array_keys($activityByVersion)));
    sort($versionSet);

    $versions = [];
    foreach ($versionSet as $v) {
        $versions[] = [
            'game_version' => $v,
            'stats' => $statsByVersion[$v] ?? null,
            'activity' => $activityByVersion[$v] ?? null,
        ];
    }

    $stmt = $pdo->prepare(
        'SELECT map_id, x, y, facing, last_seen, game_version FROM presence
         WHERE account_id = :friend_id ORDER BY last_seen DESC LIMIT 1'
    );
    $stmt->execute([':friend_id' => $friendId]);
    $presence = $stmt->fetch() ?: null;

    silphnet_json(['ok' => true, 'versions' => $versions, 'presence' => $presence]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
