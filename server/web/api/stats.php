<?php
// SilphNet - upsert the caller's own stats snapshot and/or latest activity
// message. Same shape as ping.php: requires a valid token, keyed on
// (account_id, game_version), never trusts a caller-supplied account_id.
//
// POST: token, [game_version], [badges, badges_mask, pokedex_seen,
//        pokedex_caught, league_wins, money, play_seconds, party],
//        [activity]
//
// badges_mask is a bit-per-badge snapshot (bit N per BADGE_BIT_INDEX in
// main.lua's encodeBadgeMask), separate from the plain "badges" COUNT
// above it - the gym sign feature needs to know WHICH specific badges a
// friend has (e.g. "do they have CASCADEBADGE"), which a count alone
// can't answer. Validated/clamped to fit a 16-bit mask (0-65535) the same
// defensive way every other numeric stats field here is (int) cast
// against a caller-controlled value, since a hostile or buggy client
// could otherwise send an out-of-range int for a SMALLINT UNSIGNED column.
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

$version = strtoupper(trim($_POST['game_version'] ?? $_GET['game_version'] ?? 'UNKNOWN'));
if (!in_array($version, ['RED', 'BLUE', 'YELLOW', 'GOLD', 'SILVER', 'CRYSTAL', 'UNKNOWN'], true)) $version = 'UNKNOWN';

$hasStats = isset($_POST['badges']) || isset($_GET['badges']) || isset($_POST['badges_mask']) || isset($_GET['badges_mask'])
    || isset($_POST['pokedex_seen']) || isset($_GET['pokedex_seen'])
    || isset($_POST['pokedex_caught']) || isset($_GET['pokedex_caught']) || isset($_POST['league_wins']) || isset($_GET['league_wins']) || isset($_POST['money']) || isset($_GET['money'])
    || isset($_POST['play_seconds']) || isset($_GET['play_seconds']) || isset($_POST['party']) || isset($_GET['party']);
$activity = rtrim($_POST['activity'] ?? $_GET['activity'] ?? '', " \t\0\x0B");

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
        $party = substr((string)($_POST['party'] ?? $_GET['party'] ?? ''), 0, 512);

        // badges_mask clamped to [0, 65535] (fits the SMALLINT UNSIGNED
        // column) rather than trusting a raw (int) cast the way the other
        // fields here do - the other fields' columns are wide enough that
        // an absurd input just gets silently truncated by MySQL, but a
        // negative int cast from e.g. a malformed float would otherwise
        // fail the INSERT outright against an UNSIGNED column.
        $badgesMask = (int)($_POST['badges_mask'] ?? $_GET['badges_mask'] ?? 0);
        if ($badgesMask < 0) $badgesMask = 0;
        if ($badgesMask > 65535) $badgesMask = 65535;

        // league_wins is deliberately a ONE-WAY ratchet here (GREATEST of
        // the incoming value and whatever's already stored), unlike every
        // other column in this table which just takes the client's latest
        // report as-is. This is the server-side half of the .sav
        // import/export Hall-of-Fame-wipe fix (see main.lua's
        // EVENT_BEAT_CHAMPION_RIVAL floor-to-1 logic and mod.card's
        // "known" section for the full root cause): that lossy codec has
        // no way to preserve game.save.hallOfFame at all, so a save that's
        // ever re-imported can genuinely report a SMALLER league_wins
        // than what this account already, legitimately earned before.
        // Every other field here (badges, pokedex, money, play_seconds)
        // doesn't have this problem - the .sav codec DOES preserve those
        // - so only league_wins gets this special monotonic treatment;
        // applying it everywhere would risk silently masking a real future
        // bug in one of those other fields by making a wrong DECREASE
        // permanently invisible. Once an account has ever been credited
        // with N clears, this makes it structurally impossible for any
        // future re-import (or any other client-side bug that briefly
        // under-reports) to drag that number back down - it can only ever
        // go up from here, from any client.
        $stmt = $pdo->prepare(
            'INSERT INTO friend_stats
               (account_id, game_version, badges, badges_mask, pokedex_seen, pokedex_caught, league_wins, money, play_seconds, party, updated_at)
             VALUES
               (:account_id, :version, :badges, :badges_mask, :seen, :caught, :wins, :money, :play_seconds, :party, NOW())
             ON DUPLICATE KEY UPDATE
               badges = VALUES(badges), badges_mask = VALUES(badges_mask), pokedex_seen = VALUES(pokedex_seen),
               pokedex_caught = VALUES(pokedex_caught), league_wins = GREATEST(VALUES(league_wins), league_wins),
               money = VALUES(money), play_seconds = VALUES(play_seconds), party = VALUES(party), updated_at = NOW()'
        );
        $stmt->execute([
            ':account_id' => $account['account_id'], ':version' => $version,
            ':badges' => (int)($_POST['badges'] ?? $_GET['badges'] ?? 0),
            ':badges_mask' => $badgesMask,
            ':seen' => (int)($_POST['pokedex_seen'] ?? $_GET['pokedex_seen'] ?? 0),
            ':caught' => (int)($_POST['pokedex_caught'] ?? $_GET['pokedex_caught'] ?? 0),
            ':wins' => (int)($_POST['league_wins'] ?? $_GET['league_wins'] ?? 0),
            ':money' => (int)($_POST['money'] ?? $_GET['money'] ?? 0),
            ':play_seconds' => (int)($_POST['play_seconds'] ?? $_GET['play_seconds'] ?? 0),
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
