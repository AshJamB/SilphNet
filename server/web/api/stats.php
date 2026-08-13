<?php
// SilphNet - upsert the caller's own stats snapshot and/or latest activity
// message. Same shape as ping.php: requires a valid token, keyed on
// (account_id, game_version), never trusts a caller-supplied account_id.
//
// POST: token, [game_version], [badges, pokedex_seen, pokedex_caught,
//        league_wins, money, play_seconds, party], [activity]
//
// party is main.lua's encodePartySnapshot() output - an opaque delimited
// string (see schema.sql's comment on friend_stats.party for the exact
// format). Never parsed here, only passed through to the party column
// as-is; substr-capped defensively same as activity, in case a mod-side
// bug ever sends something longer than the column's measured worst case.
//
// activity is TWO display lines joined by a literal "\n" (e.g.
// "CAUGHT LVL 25\nBLASTOISE" - see main.lua's queueCatchActivity) - NOT
// trimmed with PHP's trim(), which strips "\n" by itself along with
// other whitespace and would silently destroy the line break right at
// the door. rtrim($s, " \t\0\x0B") strips the same stray whitespace
// trim() would, explicitly EXCLUDING \r and \n, so a genuine two-line
// message survives intact while accidental trailing spaces still don't.
//
// Stats fields are all optional together - a client uploading a fresh
// stats snapshot won't necessarily have a new activity message at the
// same moment, and vice versa (an activity event fires the instant it
// happens, independent of the slower stats cycle - see main.lua). At
// least one of "any stats field present" or "activity present" must be
// given, or there's nothing to do.
//
// Returns: {"ok":true}

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();

$version = strtoupper(trim($_POST['game_version'] ?? 'UNKNOWN'));
if (!in_array($version, ['RED', 'BLUE', 'YELLOW', 'GOLD', 'UNKNOWN'], true)) $version = 'UNKNOWN';

$hasStats = isset($_POST['badges']) || isset($_POST['pokedex_seen'])
    || isset($_POST['pokedex_caught']) || isset($_POST['league_wins']) || isset($_POST['money'])
    || isset($_POST['play_seconds']) || isset($_POST['party']);
$activity = rtrim($_POST['activity'] ?? '', " \t\0\x0B");

if (!$hasStats && $activity === '') {
    silphnet_error('nothing to update: provide stats field(s) and/or activity');
}

// substr, not an error, on an over-length activity message - a mod-side
// bug that sends something too long shouldn't fail the whole request,
// just get truncated the same way every on-screen line in this project
// already gets truncated defensively.
$activity = substr($activity, 0, 32);

try {
    $pdo = silphnet_db();

    if ($hasStats) {
        // party is capped to the party column's real size (512), not
        // trimmed/altered otherwise - it's an opaque string as far as
        // this endpoint is concerned (see comment above $hasStats).
        $party = substr((string)($_POST['party'] ?? ''), 0, 512);

        $stmt = $pdo->prepare(
            'INSERT INTO friend_stats
               (account_id, game_version, badges, pokedex_seen, pokedex_caught, league_wins, money, play_seconds, party, updated_at)
             VALUES
               (:account_id, :version, :badges, :seen, :caught, :wins, :money, :play_seconds, :party, NOW())
             ON DUPLICATE KEY UPDATE
               badges = VALUES(badges), pokedex_seen = VALUES(pokedex_seen),
               pokedex_caught = VALUES(pokedex_caught), league_wins = VALUES(league_wins),
               money = VALUES(money), play_seconds = VALUES(play_seconds), party = VALUES(party), updated_at = NOW()'
        );
        $stmt->execute([
            ':account_id' => $account['account_id'], ':version' => $version,
            ':badges' => (int)($_POST['badges'] ?? 0),
            ':seen' => (int)($_POST['pokedex_seen'] ?? 0),
            ':caught' => (int)($_POST['pokedex_caught'] ?? 0),
            ':wins' => (int)($_POST['league_wins'] ?? 0),
            ':money' => (int)($_POST['money'] ?? 0),
            ':play_seconds' => (int)($_POST['play_seconds'] ?? 0),
            ':party' => $party,
        ]);
    }

    if ($activity !== '') {
        $stmt = $pdo->prepare(
            'INSERT INTO friend_activity (account_id, game_version, message, created_at)
             VALUES (:account_id, :version, :message, NOW())
             ON DUPLICATE KEY UPDATE message = VALUES(message), created_at = NOW()'
        );
        $stmt->execute([
            ':account_id' => $account['account_id'], ':version' => $version, ':message' => $activity,
        ]);
    }

    silphnet_json(['ok' => true]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
