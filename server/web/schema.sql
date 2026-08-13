-- SilphNet - schema for jamshark_silphnet
-- Run this in phpMyAdmin's SQL tab. Safe to re-run - every statement is
-- CREATE TABLE IF NOT EXISTS, so running this again after tables already
-- exist just does nothing (harmlessly).
--
-- IMPORTANT: this file only ever CREATES tables - it does NOT add new
-- columns to a table that already exists (IF NOT EXISTS only guards
-- whether the table itself is created, not its columns). When a new
-- version of SilphNet adds a column to an existing table, that column
-- addition ships in migrations.sql instead - run any new entries there
-- once, after re-running this file.
--
-- Replaces the old TCP server's local accounts.json - accounts now live
-- here, checked by password hash (bcrypt via PHP's password_hash/verify,
-- never stored or recoverable in plaintext - not even you can look it up).
--
-- Presence is keyed on (account_id, game_version) so one account can have
-- several active saves (Red/Blue/Yellow) tracked as separate "characters",
-- each with their own last-known position - see ping.php.

CREATE TABLE IF NOT EXISTS accounts (
  account_id     VARCHAR(16) NOT NULL PRIMARY KEY,   -- e.g. 24275CB2, matches the old TCP account id style
  name           VARCHAR(16) NOT NULL UNIQUE,
  password_hash  VARCHAR(255) NOT NULL,               -- PHP password_hash() output (bcrypt) - one-way, never plaintext
  trainer_id     SMALLINT UNSIGNED NOT NULL UNIQUE,    -- 0-65535, displayed zero-padded to 5 digits (00000-65535) - same range as the real games' 16-bit trainer ID
  created_at     DATETIME NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sessions (
  token       VARCHAR(64) NOT NULL PRIMARY KEY,       -- random session token, cached client-side (mod.save), same role the old TCP device token played
  account_id  VARCHAR(16) NOT NULL,
  created_at  DATETIME NOT NULL,
  last_used   DATETIME NOT NULL,                       -- bumped on every successful login_token.php check; sessions unused past SESSION_MAX_AGE_DAYS (auth.php) are rejected and deleted, so this table can't grow forever
  INDEX idx_account (account_id),
  INDEX idx_last_used (last_used)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS presence (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  account_id   VARCHAR(16) NOT NULL,
  game_version VARCHAR(16) NOT NULL DEFAULT 'UNKNOWN', -- RED | BLUE | YELLOW | GOLD | UNKNOWN
  name         VARCHAR(16) NOT NULL,
  map_id       VARCHAR(64) NOT NULL,
  x            INT NOT NULL,
  y            INT NOT NULL,
  facing       VARCHAR(8) NOT NULL DEFAULT 'down',
  last_seen    DATETIME NOT NULL,
  UNIQUE KEY uniq_account_version (account_id, game_version),
  INDEX idx_last_seen (last_seen)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS friends (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  account_id   VARCHAR(16) NOT NULL,
  friend_id    VARCHAR(16) NOT NULL,
  status       ENUM('pending','accepted') NOT NULL DEFAULT 'pending',
  created_at   DATETIME NOT NULL,
  UNIQUE KEY uniq_pair (account_id, friend_id),
  INDEX idx_account (account_id),
  INDEX idx_friend (friend_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Self-reported stats snapshot, uploaded by each client on a slower cycle
-- than presence (stats don't need to be second-fresh - see stats.php).
-- One row per (account_id, game_version), same key shape as presence, for
-- the same reason: an account can have several active saves tracked as
-- separate "characters". league_wins is #save.hallOfFame entries, badges
-- is derived client-side from save.inventory + constants.badges (see
-- main.lua's countBadges() - Badges.count() itself isn't mod-accessible).
CREATE TABLE IF NOT EXISTS friend_stats (
  account_id     VARCHAR(16) NOT NULL,
  game_version   VARCHAR(16) NOT NULL DEFAULT 'UNKNOWN',
  badges         TINYINT UNSIGNED NOT NULL DEFAULT 0,
  pokedex_seen   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  pokedex_caught SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  league_wins    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  money          INT UNSIGNED NOT NULL DEFAULT 0,
  updated_at     DATETIME NOT NULL,
  PRIMARY KEY (account_id, game_version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Latest self-reported activity message per (account_id, game_version) -
-- deliberately just ONE row per character, overwritten on every new
-- event, not a history log. message is stored as TWO lines joined by a
-- literal "\n" (e.g. "CAUGHT LVL 25\nBLASTOISE" - split back into two
-- lines only where it's drawn, in main.lua's SilphNetFriendDetail) rather
-- than one combined line, since a long species name plus the level
-- prefix risked overflowing the mod's 16-char/line display budget on one
-- line. Each half is separately capped at 16 chars client-side
-- (queueCatchActivity in main.lua), so the worst case ("CAUGHT LVL 100" +
-- "\n" + a 16-char name) is 31 bytes - comfortably inside VARCHAR(32).
-- created_at is the event's own timestamp, independent of
-- presence.last_seen - catching something and being last seen online are
-- different moments (you can catch something then walk offline, or the
-- reverse), so the friend detail screen shows both times separately
-- rather than conflating them.
CREATE TABLE IF NOT EXISTS friend_activity (
  account_id    VARCHAR(16) NOT NULL,
  game_version  VARCHAR(16) NOT NULL DEFAULT 'UNKNOWN',
  message       VARCHAR(32) NOT NULL,
  created_at    DATETIME NOT NULL,
  PRIMARY KEY (account_id, game_version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
