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

-- email is OPTIONAL (nullable) - registering in-game never asks for one, so
-- most accounts will have NULL here unless the player later sets one via
-- account.php specifically to enable password recovery. Stored encrypted
-- (AES-256-GCM, see email_crypto.php) rather than plain text - the raw
-- ciphertext in this column is meaningless without EMAIL_ENCRYPTION_KEY
-- (a secret defined in db.php, never committed to git), so a database
-- dump alone doesn't expose anyone's real email address. This is
-- reversible encryption, not one-way hashing like password_hash - the
-- server has to be able to read the real address back out to actually
-- send a recovery email to it, which a hash could never allow.
CREATE TABLE IF NOT EXISTS accounts (
  account_id     VARCHAR(16) NOT NULL PRIMARY KEY,   -- e.g. 24275CB2, matches the old TCP account id style
  name           VARCHAR(16) NOT NULL UNIQUE,
  password_hash  VARCHAR(255) NOT NULL,               -- PHP password_hash() output (bcrypt) - one-way, never plaintext
  trainer_id     SMALLINT UNSIGNED NOT NULL UNIQUE,    -- 0-65535, displayed zero-padded to 5 digits (00000-65535) - same range as the real games' 16-bit trainer ID
  email          VARBINARY(512) NULL,                  -- AES-256-GCM ciphertext (nonce+tag+ciphertext packed together by email_crypto.php), NULL if never set
  created_at     DATETIME NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Password reset tokens, requested via request_password_reset.php and
-- consumed via reset_password.php. One row per request - a new request
-- doesn't overwrite an old unused one, so a stale link that was never
-- clicked simply expires on its own (see expires_at) rather than needing
-- active cleanup. used_at is set the moment a token is successfully
-- consumed, so a reset link can only ever be used once even within its
-- validity window - re-visiting the same link after a successful reset
-- (e.g. clicking it twice, or an email client "pre-fetching" the link)
-- correctly fails rather than silently resetting the password again.
CREATE TABLE IF NOT EXISTS password_resets (
  token       VARCHAR(64) NOT NULL PRIMARY KEY,   -- random token, same shape as sessions.token
  account_id  VARCHAR(16) NOT NULL,
  created_at  DATETIME NOT NULL,
  expires_at  DATETIME NOT NULL,
  used_at     DATETIME NULL,
  INDEX idx_account (account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sessions (
  token       VARCHAR(64) NOT NULL PRIMARY KEY,       -- random session token, cached client-side (mod.save), same role the old TCP device token played
  account_id  VARCHAR(16) NOT NULL,
  created_at  DATETIME NOT NULL,
  last_used   DATETIME NOT NULL,                       -- bumped on every successful login_token.php check; sessions unused past SESSION_MAX_AGE_DAYS (auth.php) are rejected and deleted, so this table can't grow forever
  INDEX idx_account (account_id),
  INDEX idx_last_used (last_used)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- No "name" column - a fresh setup never gets the denormalized
-- presence.name column an earlier version of this schema had (it was
-- written on every ping but never actually read back by any endpoint;
-- every real name display joins to accounts.name fresh instead - see
-- migrations.sql's 2026-08-13 dated entry for the removal on an
-- EXISTING database, and ping.php's INSERT for why it's gone from
-- there too).
CREATE TABLE IF NOT EXISTS presence (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  account_id   VARCHAR(16) NOT NULL,
  game_version VARCHAR(16) NOT NULL DEFAULT 'UNKNOWN', -- RED | BLUE | YELLOW | GOLD | SILVER | CRYSTAL | UNKNOWN
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
-- separate "characters". league_wins is #save.hallOfFame entries on a
-- Gen 1 save (save.hallOfFame.count on a Gen 2/Gold/Silver save - a
-- differently-shaped field there, not the same one read differently).
-- badges is derived client-side: from save.inventory + constants.badges
-- on Gen 1 (Badges.count() itself isn't mod-accessible), or from
-- save.player.badges + save.player.kantoBadges directly on Gen 2, which
-- carries no badge items at all - see main.lua's countBadges()/isGen2().
-- play_seconds is a normalized TOTAL SECONDS count - save.playTime has
-- two possible shapes engine-side (plain seconds, or an {hours,minutes,
-- seconds,frames} table), both collapsed to one plain integer client-side
-- (main.lua's readPlaySeconds()) so this column only ever has one shape
-- to deal with.
-- party is up to 6 mons encoded as ONE delimited string by main.lua's
-- encodePartySnapshot() - "SPECIES,LEVEL,HP,MAXHP,MOVE1|MOVE2|MOVE3|MOVE4"
-- per mon, semicolon-joined across mons - following this project's usual
-- "no JSON library available" convention (same as friend_activity's
-- "\n"-joined two-line messages) rather than a JSON payload. VARCHAR(255)
-- comfortably covers the realistic worst case (6 mons, each with the
-- longest real Gen 1 species name and 4 long move names, comes to well
-- under 255 chars) with room to spare. Stored/returned completely opaque
-- server-side - this column is never parsed in PHP, only passed through
-- untouched (see stats.php/friend_detail.php); all encoding/decoding
-- happens client-side in main.lua.
--
-- VARCHAR(512), not (255) - actually calculated (not guessed) against the
-- real worst case: 6 mons, each with the longest real Gen 1 species name
-- (TENTACRUEL, 10 chars) and 4 copies of the longest real move name
-- (DOUBLE-EDGE, 11 chars) comes to 425 chars ("TENTACRUEL,100,714,714,
-- DOUBLE-EDGE|DOUBLE-EDGE|DOUBLE-EDGE|DOUBLE-EDGE" x6, semicolon-joined) -
-- confirmed by literally constructing that string and measuring it, not
-- estimated by eye. 512 leaves real headroom above that measured worst
-- case rather than cutting it close.
CREATE TABLE IF NOT EXISTS friend_stats (
  account_id     VARCHAR(16) NOT NULL,
  game_version   VARCHAR(16) NOT NULL DEFAULT 'UNKNOWN',
  badges         TINYINT UNSIGNED NOT NULL DEFAULT 0,
  -- Bitmask of every individual badge id this save has earned (bit N per
  -- BADGE_BIT_INDEX in main.lua - Kanto badges 0-7, Johto badges 8-15),
  -- NOT a count - "badges" above already covers "how many", this column
  -- exists so the gym sign feature can answer "does this specific friend
  -- have THIS gym's badge" without re-deriving it from anything else.
  -- SMALLINT UNSIGNED covers all 16 bits (max value 65535).
  badges_mask    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  pokedex_seen   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  pokedex_caught SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  league_wins    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  money          INT UNSIGNED NOT NULL DEFAULT 0,
  play_seconds   INT UNSIGNED NOT NULL DEFAULT 0,
  party          VARCHAR(512) NOT NULL DEFAULT '',
  -- Tiles walked in the overworld this save, counted client-side off the
  -- real world.stepped event (main.lua has no other way to know this - it
  -- isn't a field the engine's own save data tracks anywhere). Same
  -- one-way-ratchet treatment as league_wins in stats.php and for the same
  -- reason: a mod.save-backed running counter is just as vulnerable to a
  -- .sav re-import resetting it as game.save.hallOfFame was, so the SERVER
  -- side floors this at whatever's already been credited rather than
  -- trusting a client's latest report as-is. INT UNSIGNED, not SMALLINT -
  -- a lifetime walking total can realistically exceed 65535 tiles well
  -- within normal play.
  tiles_walked   INT UNSIGNED NOT NULL DEFAULT 0,
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

-- History of name/Trainer ID changes made via update_account.php - one row
-- per field actually changed (a request that changes both name AND
-- trainer_id in one go writes two rows here, not one combined row), so
-- there's an audit trail if a rename/re-ID ever needs to be traced back
-- (e.g. "who used to be Trainer ID 04815" or "when did this account's name
-- change"). account_id is the account's own permanent id - never changes,
-- so this table can always be traced back to one account regardless of how
-- many times its name/trainer_id have changed since.
CREATE TABLE IF NOT EXISTS account_history (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  account_id  VARCHAR(16) NOT NULL,
  field       ENUM('name','trainer_id') NOT NULL,
  old_value   VARCHAR(16) NOT NULL,
  new_value   VARCHAR(16) NOT NULL,
  changed_at  DATETIME NOT NULL,
  INDEX idx_account (account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
