<?php
// SilphNet presence - upsert the caller's last-known position for one
// game_version (RED/BLUE/YELLOW/GOLD/UNKNOWN - GOLD accepted for forward
// compatibility even though this mod targets Gen 1 only and main.lua
// never actually sends it today; the real engine field it's read from,
// game.save.version, can genuinely be "gold" per GameVersion.VERSIONS,
// so accepting it here now avoids a second migration later). Requires a
// valid session token now (see login.php/register.php/login_token.php) -
// a bare account_id is no longer accepted on its own, closing the
// "anyone can POST as anyone" gap the first version of this endpoint had.
//
// POST: token, map_id, x, y, facing, [game_version]
// One row per (account_id, game_version) - an account can have several
// active saves (Red/Blue/Yellow) tracked as separate "characters" at once.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();   // exits with 401 if invalid

$mapId   = trim($_POST['map_id'] ?? '');
$x       = $_POST['x'] ?? null;
$y       = $_POST['y'] ?? null;
$facing  = trim($_POST['facing'] ?? 'down');
$version = strtoupper(trim($_POST['game_version'] ?? 'UNKNOWN'));

if ($mapId === '' || $x === null || $y === null) {
    silphnet_error('missing required field(s): map_id, x, y');
}
if (!preg_match('/^-?\d+$/', (string)$x) || !preg_match('/^-?\d+$/', (string)$y)) {
    silphnet_error('x and y must be integers');
}
if (!in_array($version, ['RED', 'BLUE', 'YELLOW', 'GOLD', 'UNKNOWN'], true)) $version = 'UNKNOWN';

$mapId  = substr($mapId, 0, 64);
$facing = substr($facing, 0, 8);

try {
    $pdo = silphnet_db();

    // Re-key existing UNKNOWN rows onto the real version the moment it
    // becomes known, rather than leaving them behind as orphaned dead
    // rows once the mod starts sending a real version. This matters
    // because game_version is PART OF THE PRIMARY KEY on presence/
    // friend_stats/friend_activity (account_id, game_version) - a plain
    // upsert keyed on the NEW version can't touch an existing row under
    // the OLD (UNKNOWN) key, since as far as MySQL's ON DUPLICATE KEY
    // UPDATE is concerned that's a completely different row, not the
    // same one needing an update. Every account that pinged before this
    // version's game.save.version detection existed has exactly this
    // stale-UNKNOWN-row problem, and there's no way to tell from the
    // server side which UNKNOWN rows belong to a player whose mod
    // genuinely hasn't updated yet (still correctly UNKNOWN) versus one
    // who just updated (now stale) - so this re-keys opportunistically,
    // every single ping, only when it's actually safe to do so (see the
    // guard below), rather than via a one-off migration that would have
    // had to guess.
    //
    // Only re-keys when: (a) the incoming version isn't itself UNKNOWN
    // (nothing to upgrade to otherwise), and (b) there's no ALREADY
    // EXISTING row under the real version for this account - if one
    // already exists (e.g. this account already pinged as BLUE once
    // before, and also somehow has a leftover UNKNOWN row), re-keying
    // would collide with that existing row's primary key and fail; in
    // that rare case the UNKNOWN row is just left alone rather than
    // erroring the whole ping out, since real presence reporting for
    // the correct version already works regardless.
    if ($version !== 'UNKNOWN') {
        foreach (['presence', 'friend_stats', 'friend_activity'] as $table) {
            $check = $pdo->prepare(
                "SELECT 1 FROM $table WHERE account_id = :account_id AND game_version = :version"
            );
            $check->execute([':account_id' => $account['account_id'], ':version' => $version]);
            if (!$check->fetch()) {
                $pdo->prepare(
                    "UPDATE $table SET game_version = :version
                     WHERE account_id = :account_id AND game_version = 'UNKNOWN'"
                )->execute([':account_id' => $account['account_id'], ':version' => $version]);
            }
        }
    }

    $stmt = $pdo->prepare(
        'INSERT INTO presence (account_id, game_version, name, map_id, x, y, facing, last_seen)
         VALUES (:account_id, :version, :name, :map_id, :x, :y, :facing, NOW())
         ON DUPLICATE KEY UPDATE
           name = VALUES(name), map_id = VALUES(map_id), x = VALUES(x), y = VALUES(y),
           facing = VALUES(facing), last_seen = NOW()'
    );
    $stmt->execute([
        ':account_id' => $account['account_id'], ':version' => $version, ':name' => $account['name'],
        ':map_id' => $mapId, ':x' => (int)$x, ':y' => (int)$y, ':facing' => $facing,
    ]);
    silphnet_json(['ok' => true]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
