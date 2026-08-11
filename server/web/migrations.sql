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
