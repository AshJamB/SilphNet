<?php
// SilphNet - PUBLIC, unauthenticated online-count summary for the website
// homepage widget (index.php). Deliberately the ONLY endpoint in this
// whole project that answers without a valid session token - every other
// endpoint requires one specifically because it either identifies the
// caller or exposes another account's details. This one is safe to leave
// open because it exposes strictly less than that: no names, no Trainer
// IDs, no account_ids, nothing that identifies who is online - just how
// MANY, per version and in total. A homepage visitor who hasn't logged in
// (or doesn't even have an account) should still be able to see "N
// players online" without that meaning anyone's identity leaks.
//
// GET: (no params)
// Returns: {"ok":true,"total":8,"versions":[
//   {"game_version":"RED","count":4}, {"game_version":"BLUE","count":3},
//   {"game_version":"YELLOW","count":1}
// ]}
//
// Same RED/BLUE/YELLOW-only, UNKNOWN-excluded, 300s-online-window rules
// as online_by_version.php (see that file's own comments for why) - kept
// as a separate constant/query here rather than importing that file's
// logic, since this endpoint's whole point is to be simpler and to never
// touch the `accounts` table at all (no JOIN needed when names/IDs are
// never returned), reducing what this public-facing endpoint can ever
// expose even if it had a bug.

require __DIR__ . '/db.php';

const SILPHNET_PUBLIC_ONLINE_AFTER_SECONDS = 300;
const SILPHNET_PUBLIC_TRACKED_VERSIONS = ['RED', 'BLUE', 'YELLOW'];

try {
    $pdo = silphnet_db();
    $stmt = $pdo->prepare(
        'SELECT game_version, COUNT(*) AS c FROM presence
         WHERE game_version IN (' . implode(',', array_fill(0, count(SILPHNET_PUBLIC_TRACKED_VERSIONS), '?')) . ')
           AND last_seen >= NOW() - INTERVAL ' . SILPHNET_PUBLIC_ONLINE_AFTER_SECONDS . ' SECOND
         GROUP BY game_version'
    );
    $stmt->execute(SILPHNET_PUBLIC_TRACKED_VERSIONS);
    $rows = $stmt->fetchAll();

    $counts = [];
    foreach (SILPHNET_PUBLIC_TRACKED_VERSIONS as $v) $counts[$v] = 0;
    foreach ($rows as $r) $counts[$r['game_version']] = (int)$r['c'];

    $versions = [];
    $total = 0;
    foreach (SILPHNET_PUBLIC_TRACKED_VERSIONS as $v) {
        $versions[] = ['game_version' => $v, 'count' => $counts[$v]];
        $total += $counts[$v];
    }

    silphnet_json(['ok' => true, 'total' => $total, 'versions' => $versions]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
