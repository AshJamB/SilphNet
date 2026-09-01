-- SilphNet - column migrations for an EXISTING database.
--
-- schema.sql only creates tables that don't exist yet - it never adds a
-- column to a table you already have (CREATE TABLE IF NOT EXISTS doesn't
-- touch columns). Whenever a new SilphNet version needs a new column on an
-- existing table, the change ships here as one clearly-dated block. Run
-- each block ONCE, top to bottom, skipping any block whose column you can
-- already see in phpMyAdmin's table structure view for that table.
--
-- Plain SQL only (no stored procedures) - some shared-hosting MySQL users
-- don't have CREATE ROUTINE privileges, and plain ALTER TABLE/UPDATE works
-- on every MySQL/MariaDB version this is likely to run on.

-- ---------------------------------------------------------------------------
-- 2026-08-11: accounts.trainer_id
-- Needed if your `accounts` table was created BEFORE trainer_id existed in
-- schema.sql (i.e. you ran an earlier version of this project). If you're
-- setting up SilphNet fresh, schema.sql already creates this column and
-- you can skip this whole block.
-- ---------------------------------------------------------------------------

-- Step 1: check if the column is missing before running steps 2-4. Run
-- this first - if it returns a row, trainer_id already exists and you
-- should skip the rest of this block entirely.
--
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = DATABASE() AND table_name = 'accounts' AND column_name = 'trainer_id';
--
-- (empty result = column is missing, continue with steps 2-4 below)

-- Step 2: add the column, nullable for now (existing rows start blank -
-- that's fine, UNIQUE only compares non-NULL values against each other).
ALTER TABLE accounts ADD COLUMN trainer_id SMALLINT UNSIGNED NULL UNIQUE AFTER password_hash;

-- Step 3: fill in a random 5-digit id (0-65535, matching register.php's
-- own range) for every row that doesn't have one yet. Safe to run more
-- than once - it only touches rows still NULL. If you have more than a
-- couple of accounts, a random collision is possible on one pass; just
-- run this line again afterward and it'll pick up any still-NULL rows.
UPDATE accounts SET trainer_id = FLOOR(RAND() * 65536) WHERE trainer_id IS NULL;

-- Step 4: once step 3 has left NO rows with trainer_id IS NULL (check with
-- `SELECT COUNT(*) FROM accounts WHERE trainer_id IS NULL;` - must return 0),
-- tighten the column to match schema.sql's definition exactly:
ALTER TABLE accounts MODIFY COLUMN trainer_id SMALLINT UNSIGNED NOT NULL UNIQUE;

-- ---------------------------------------------------------------------------
-- 2026-08-11: sessions.last_used (+ expiry)
-- Every real login (not a cached-token reconnect) was inserting a session
-- row that never got deleted or expired anywhere - an unbounded, forever-
-- growing table. Needed if your `sessions` table was created BEFORE this
-- column existed in schema.sql. If you're setting up SilphNet fresh,
-- schema.sql already creates this column and you can skip this block.
-- ---------------------------------------------------------------------------

-- Step 1: check if the column is missing first - if this returns a row,
-- last_used already exists and you should skip the rest of this block.
--
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = DATABASE() AND table_name = 'sessions' AND column_name = 'last_used';

-- Step 2: add the column, backfilled from created_at for existing rows
-- (a reasonable starting point - they'll get a real last_used the next
-- time each token is actually used, or expire if it never is again).
ALTER TABLE sessions ADD COLUMN last_used DATETIME NULL AFTER created_at;
UPDATE sessions SET last_used = created_at WHERE last_used IS NULL;
ALTER TABLE sessions MODIFY COLUMN last_used DATETIME NOT NULL;
ALTER TABLE sessions ADD INDEX idx_last_used (last_used);

-- Step 3: one-off cleanup of anything already stale under the new 90-day
-- cutoff (auth.php enforces this going forward on every login_token.php
-- call - this step just clears out any backlog from before that existed).
DELETE FROM sessions WHERE last_used < NOW() - INTERVAL 90 DAY;

-- ---------------------------------------------------------------------------
-- 2026-08-13: friend_stats + friend_activity (new tables, not a column
-- migration) - just re-run schema.sql, its CREATE TABLE IF NOT EXISTS
-- statements will add these two new tables without touching anything you
-- already have. Nothing to ALTER here - listed in this file only so it's
-- not missed by anyone skimming straight to migrations.sql for "what do I
-- need to run for this version."
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2026-08-14: UNKNOWN game_version rows - NO SQL TO RUN, self-healing.
-- Before this version, gameVersion in main.lua was a permanent "UNKNOWN"
-- placeholder (never actually wired up to the engine), so every existing
-- presence/friend_stats/friend_activity row is currently keyed UNKNOWN.
-- game_version is PART OF THE PRIMARY KEY on all three tables, so once
-- clients start sending a real version (RED/BLUE/YELLOW), a naive upsert
-- can't just overwrite the old UNKNOWN row in place - it would insert a
-- SECOND row under the new key instead, leaving the old UNKNOWN row
-- behind as permanent dead data.
--
-- Fixed in ping.php itself, not here: every ping now re-keys an existing
-- UNKNOWN row (on all three tables) onto the real version the moment
-- it's known, PROVIDED no row already exists under that real version for
-- the same account - see the comment block above ping.php's INSERT for
-- the exact logic and why that guard is needed. This runs automatically,
-- once per account, the first time each player's updated client pings -
-- no manual SQL, no need to guess which UNKNOWN rows are stale (already
-- updated) versus genuinely current (mod not updated yet), since the
-- server can't tell those apart from a one-off migration but CAN handle
-- it correctly live, one real ping at a time, as each player updates.
--
-- If you want to check progress: `SELECT COUNT(*) FROM presence WHERE
-- game_version = 'UNKNOWN';` - this number should fall towards zero (not
-- necessarily reach it - a few real edge cases, like a save the engine
-- itself can't identify, may legitimately stay UNKNOWN) as more players
-- update and play at least once.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2026-08-14: friend_stats.play_seconds
-- Needed if your friend_stats table was created BEFORE this column
-- existed in schema.sql. If you're setting up SilphNet fresh, schema.sql
-- already creates this column and you can skip this block.
-- ---------------------------------------------------------------------------

-- Step 1: check if the column is missing before running step 2 - if this
-- returns a row, play_seconds already exists and you should skip this
-- whole block.
--
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = DATABASE() AND table_name = 'friend_stats' AND column_name = 'play_seconds';

-- Step 2: add the column, defaulted to 0 for existing rows - they'll get
-- a real value the next time that account's client uploads a stats
-- snapshot (~every 3 minutes of play, same as any other stats field).
ALTER TABLE friend_stats ADD COLUMN play_seconds INT UNSIGNED NOT NULL DEFAULT 0 AFTER money;
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2026-08-13: friend_stats.party
-- Needed if your friend_stats table was created BEFORE this column
-- existed in schema.sql. If you're setting up SilphNet fresh, schema.sql
-- already creates this column and you can skip this block.
-- ---------------------------------------------------------------------------

-- Step 1: check if the column is missing before running step 2 - if this
-- returns a row, party already exists and you should skip this whole
-- block.
--
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = DATABASE() AND table_name = 'friend_stats' AND column_name = 'party';

-- Step 2: add the column, defaulted to empty for existing rows - they'll
-- get a real value the next time that account's client uploads a stats
-- snapshot (~every 3 minutes of play, same as any other stats field).
-- VARCHAR(512), not (255) - see schema.sql's comment above this same
-- column for the measured (not guessed) worst-case size this was sized
-- against.
ALTER TABLE friend_stats ADD COLUMN party VARCHAR(512) NOT NULL DEFAULT '' AFTER play_seconds;
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2026-08-13: presence.name removed (dead column, not a new one)
-- presence.name was a denormalized copy of the display name, written on
-- every ping.php call but never actually READ back by any endpoint -
-- friends.php/nearby.php/online_by_version.php/friend_detail.php all
-- join to accounts.name fresh instead. Harmless as-is (self-corrected
-- within one ping after a rename, since ping.php overwrote it every
-- ~30s regardless), but it was the one column that could have looked
-- like a real "stale name after rename" bug to anyone reading this
-- schema without checking whether it was actually used - removed while
-- building update_account.php's rename feature specifically to close
-- off that question for good. If you're setting up SilphNet fresh,
-- schema.sql no longer creates this column at all and you can skip this
-- block entirely.
-- ---------------------------------------------------------------------------

-- Step 1: check if the column still exists before running step 2 - if
-- this returns NO rows, it's already gone (or you're on a fresh
-- install) and you can skip the rest of this block.
--
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = DATABASE() AND table_name = 'presence' AND column_name = 'name';

-- Step 2: drop it. Safe to run even while players are actively pinging -
-- ping.php's own INSERT no longer references this column at all (see
-- that file), so there's no window where a live request could fail
-- because the column vanished mid-use.
ALTER TABLE presence DROP COLUMN name;
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2026-08-13: account_history (new table, not a column migration) - just
-- re-run schema.sql, its CREATE TABLE IF NOT EXISTS will add this table
-- without touching anything you already have. Nothing to ALTER here -
-- listed in this file only so it's not missed by anyone skimming straight
-- to migrations.sql for "what do I need to run for this version." Logs
-- every name/Trainer ID change made via update_account.php going forward -
-- it has no historical data for changes made before this table existed.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2026-08-13: accounts.email + password_resets (recovery email feature)
-- Needed if your accounts table was created BEFORE the email column
-- existed in schema.sql. If you're setting up SilphNet fresh, schema.sql
-- already creates both and you can skip this block.
--
-- IMPORTANT: before running step 2 below, you must set EMAIL_ENCRYPTION_KEY
-- in db.php (see db.php.example for the exact constant name/format) - the
-- email column stores AES-256-GCM ciphertext, not plain text, and nothing
-- reads/writes it correctly without that key defined.
-- ---------------------------------------------------------------------------

-- Step 1: check if the column is missing before running step 2 - if this
-- returns a row, email already exists and you should skip step 2.
--
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = DATABASE() AND table_name = 'accounts' AND column_name = 'email';
--
-- (if information_schema access is denied on your host, as some shared
-- cPanel MySQL users find, just try step 2 directly - MySQL itself will
-- error harmlessly with "Duplicate column name" if it already exists)

-- Step 2: add the column, nullable - every existing account simply has no
-- recovery email set until its owner adds one via account.php.
ALTER TABLE accounts ADD COLUMN email VARBINARY(512) NULL AFTER trainer_id;

-- Step 3: password_resets is a brand new table, not a column addition -
-- just re-run schema.sql, its CREATE TABLE IF NOT EXISTS will add it
-- without touching anything else.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2026-08-21: friend_stats.badges_mask (gym sign + league leaderboard sign)
-- Needed if your `friend_stats` table was created BEFORE badges_mask
-- existed in schema.sql. If you're setting up SilphNet fresh, schema.sql
-- already creates this column and you can skip this whole block.
--
-- badges_mask is a bit-per-badge snapshot (bit N per BADGE_BIT_INDEX in
-- main.lua), distinct from the existing "badges" column which only ever
-- stored a plain count - the new gym sign feature needs to answer "does
-- this friend have THIS SPECIFIC gym's badge", which a count alone can't
-- answer (two 4-badge trainers can have completely different four
-- badges). Existing rows simply default to 0 (no bits set) until each
-- client's next stats upload backfills its real mask - harmless in the
-- interim, a gym sign just shows "no friends have this badge yet" for
-- anyone who hasn't re-uploaded since updating.
-- ---------------------------------------------------------------------------

-- Step 1: check if the column is missing before running step 2 - if this
-- returns a row, badges_mask already exists and you should skip step 2.
--
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = DATABASE() AND table_name = 'friend_stats' AND column_name = 'badges_mask';
--
-- (empty result = column is missing, continue with step 2 below)

-- Step 2: add the column, defaulting every existing row to 0 (no badges
-- known yet) - safe to run while players are actively uploading stats,
-- since stats.php's own upsert doesn't require this column to already
-- exist for its OTHER fields to keep working.
ALTER TABLE friend_stats ADD COLUMN badges_mask SMALLINT UNSIGNED NOT NULL DEFAULT 0 AFTER badges;
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2026-08-28: presence's unique key widened to (account_id, game_version)
-- Needed if your `presence` table predates the multi-version tracking
-- feature (an install from before Gold/Silver/Yellow-alongside-Red/Blue
-- support existed) - it would have been created with a unique key on
-- account_id ALONE (one row per account, full stop), which schema.sql's
-- CREATE TABLE IF NOT EXISTS never retroactively widens on an existing
-- table. This migration was missed when the multi-version feature first
-- shipped and went unnoticed for a long time, because the symptom is
-- subtle: ping.php's INSERT ... ON DUPLICATE KEY UPDATE deliberately never
-- rewrites game_version on a match (it assumes that column is already part
-- of what identified the row) - so on an unwidened table, EVERY ping for
-- any version collides with the same single existing row, silently
-- refreshing its position/last_seen while game_version stays frozen
-- forever on whichever version first created that row. Every ping still
-- succeeds (200 OK) and carries the correct version - it just isn't
-- allowed to land in its own row - so this can look exactly like a client
-- detection bug (reported as "SN ONLINE shows me as my OLD game, not the
-- one I'm actually playing") even though the client was correct the whole
-- time. Confirmed directly on a real install via SHOW INDEX FROM presence
-- rather than guessed, after three client-side fixes in a row failed to
-- change the symptom - the real bug was never in main.lua.
--
-- If you're setting up SilphNet fresh, schema.sql already creates this key
-- correctly (UNIQUE KEY uniq_account_version (account_id, game_version))
-- and you can skip this whole block.
-- ---------------------------------------------------------------------------

-- Step 1: check which key you actually have - run this first.
--
--   SHOW INDEX FROM presence;
--
-- If you see a key (any name) covering ONLY account_id with nothing else
-- under it, you need this migration. If you already see account_id AND
-- game_version listed together under the same key name, skip this block -
-- your table is already correct.

-- Step 2: drop the too-narrow key and add the correct composite one. Safe
-- to run live - this doesn't touch any existing data, only what future
-- pings are allowed to do. Replace uniq_account below with whatever
-- Key_name step 1 actually showed you, if it's different.
ALTER TABLE presence DROP INDEX uniq_account;
ALTER TABLE presence ADD UNIQUE KEY uniq_account_version (account_id, game_version);
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2026-09-01: friend_stats.tiles_walked (SN RECORDS tiles-walked leaderboard)
-- Needed if your `friend_stats` table was created BEFORE tiles_walked
-- existed in schema.sql. If you're setting up SilphNet fresh, schema.sql
-- already creates this column and you can skip this whole block.
-- ---------------------------------------------------------------------------

-- Step 1: check if the column is missing before running step 2 - if this
-- returns a row, tiles_walked already exists and you should skip step 2.
--
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = DATABASE() AND table_name = 'friend_stats' AND column_name = 'tiles_walked';
--
-- (empty result = column is missing, continue with step 2 below)

-- Step 2: add the column, defaulting every existing row to 0 - safe to run
-- while players are actively uploading stats, since stats.php's own
-- upsert doesn't require this column to already exist for its OTHER
-- fields to keep working.
ALTER TABLE friend_stats ADD COLUMN tiles_walked INT UNSIGNED NOT NULL DEFAULT 0 AFTER party;
-- ---------------------------------------------------------------------------
