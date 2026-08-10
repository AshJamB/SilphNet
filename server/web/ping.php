<?php
// SilphNet presence - upsert the caller's last-known position for one
// game_version (RED/BLUE/YELLOW/UNKNOWN). Requires a valid session token
// now (see login.php/register.php/login_token.php) - a bare account_id is
// no longer accepted on its own, closing the "anyone can POST as anyone"
// gap the first version of this endpoint had.
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
if (!in_array($version, ['RED', 'BLUE', 'YELLOW', 'UNKNOWN'], true)) $version = 'UNKNOWN';

$mapId  = substr($mapId, 0, 64);
$facing = substr($facing, 0, 8);

try {
    $pdo = silphnet_db();
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
