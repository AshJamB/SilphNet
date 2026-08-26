<?php
// SilphNet - PUBLIC, unauthenticated player list for one game version, for
// the website homepage's online-status modal drilldown. Deliberately a
// SEPARATE endpoint from public_online_status.php (which stays
// counts-only) rather than adding an optional "include names" flag to
// that one - keeping "this endpoint never exposes identity" and "this
// endpoint does expose identity, on purpose" as two clearly different
// files makes it obvious at a glance which is which, rather than a single
// file whose safety depends on a caller-supplied flag being handled
// correctly every time.
//
// This DOES expose names + Trainer IDs with no login required - a
// deliberate choice (confirmed directly) for this project's scale (a
// small friends/community server), matching the level of detail the
// in-game SN ONLINE screen already shows to any logged-in player. Anyone
// who can already see a Trainer ID in-game (nearby, friends, SN ONLINE)
// could already learn it there; this just makes the same "who's online"
// information reachable from the website too, without requiring a login
// just to look.
//
// GET: game_version=RED|BLUE|YELLOW|GOLD|SILVER|CRYSTAL
// Returns: {"ok":true,"game_version":"RED","count":4,"players":[
//   {"name":"...","trainer_id":"04815","map_id":"VICTORY_ROAD"}, ...
// ]}
//
// account_id is deliberately NOT included here (unlike online_by_version.php,
// which needs it for the in-game add-friend flow) - a website visitor has
// no add-friend action to take from this modal, so there's no reason to
// hand out that identifier at all.
//
// map_id is the raw internal id (e.g. "VICTORY_ROAD"), not a friendly
// display name - main.lua's FRIENDLY_MAP_NAMES lookup table (the thing
// that turns this into "VICTORY ROAD" in-game) is client-side Lua only,
// not reachable from PHP. Rather than duplicating that whole table here
// in a second language to keep in sync forever, the modal's own JS does
// the same simple "_" -> " " fallback formatting main.lua itself falls
// back to for any map not in its explicit table - which already produces
// a correct, readable result for the overwhelming majority of real map
// ids (e.g. VICTORY_ROAD, ROUTE_11) without needing the full table at all.

require __DIR__ . '/db.php';

const SILPHNET_PUBLIC_ONLINE_AFTER_SECONDS = 300;
const SILPHNET_PUBLIC_TRACKED_VERSIONS = ['RED', 'BLUE', 'YELLOW', 'GOLD', 'SILVER', 'CRYSTAL'];

$version = strtoupper(trim($_GET['game_version'] ?? ''));
if (!in_array($version, SILPHNET_PUBLIC_TRACKED_VERSIONS, true)) {
    silphnet_error('game_version must be one of RED, BLUE, YELLOW, GOLD, SILVER, CRYSTAL');
}

try {
    $pdo = silphnet_db();
    $stmt = $pdo->prepare(
        'SELECT a.name, a.trainer_id, p.map_id
         FROM presence p
         JOIN accounts a ON a.account_id = p.account_id
         WHERE p.game_version = :version
           AND p.last_seen >= NOW() - INTERVAL ' . SILPHNET_PUBLIC_ONLINE_AFTER_SECONDS . ' SECOND
         GROUP BY p.account_id, a.name, a.trainer_id, p.map_id
         ORDER BY a.name ASC'
    );
    $stmt->execute([':version' => $version]);
    $rows = $stmt->fetchAll();
    foreach ($rows as &$r) $r['trainer_id'] = str_pad($r['trainer_id'], 5, '0', STR_PAD_LEFT);

    silphnet_json(['ok' => true, 'game_version' => $version, 'count' => count($rows), 'players' => $rows]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
