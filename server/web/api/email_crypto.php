<?php
// SilphNet accounts - reversible encryption for accounts.email.
//
// This is NOT the same kind of protection password_hash() gives passwords -
// that's one-way (can only ever be verified, never read back), which is
// exactly right for a password but useless for an email address the
// server needs to actually read in order to send a recovery link to it.
// This is AES-256-GCM instead: real encryption, real decryption, using one
// secret key (EMAIL_ENCRYPTION_KEY, defined in db.php - never committed to
// git, same treatment as DB_PASS). Anyone with that key and a database
// dump can recover every email address; anyone with ONLY the database dump
// (e.g. a leaked backup, a compromised low-privilege DB user) sees nothing
// but random-looking bytes.
//
// GCM is an AUTHENTICATED mode - decryption fails loudly (returns null,
// never garbage) if the ciphertext has been tampered with or truncated,
// rather than silently producing corrupted plaintext. Each encryption
// uses a fresh random 12-byte nonce (openssl_random_pseudo_bytes), packed
// together with the 16-byte auth tag and the ciphertext itself into ONE
// binary blob - so accounts.email can stay a single VARBINARY column
// rather than needing three separate columns for nonce/tag/ciphertext.
//
// Layout of the packed blob: [12 bytes nonce][16 bytes tag][ciphertext]

require_once __DIR__ . '/db.php';   // for EMAIL_ENCRYPTION_KEY

const SILPHNET_EMAIL_CIPHER = 'aes-256-gcm';
const SILPHNET_EMAIL_NONCE_LEN = 12;
const SILPHNET_EMAIL_TAG_LEN = 16;

// Encrypts a plaintext email address for storage. Returns raw binary
// (safe to bind directly as a PDO param - PDO handles binary strings fine
// as long as the column is VARBINARY, not VARCHAR/TEXT, which would
// mangle non-UTF8 bytes on some charsets).
function silphnet_encrypt_email($plaintext) {
    $key = silphnet_email_key();
    $nonce = openssl_random_pseudo_bytes(SILPHNET_EMAIL_NONCE_LEN);
    $tag = '';
    $ciphertext = openssl_encrypt(
        $plaintext, SILPHNET_EMAIL_CIPHER, $key, OPENSSL_RAW_DATA,
        $nonce, $tag, '', SILPHNET_EMAIL_TAG_LEN
    );
    if ($ciphertext === false) return null;
    return $nonce . $tag . $ciphertext;
}

// Decrypts a packed blob back to the plaintext email. Returns null (never
// throws, never returns garbage) if the blob is missing, too short to be
// valid, or fails GCM's built-in tamper check - callers should treat null
// the same as "no email on file", not surface a raw decryption error.
function silphnet_decrypt_email($blob) {
    if ($blob === null || $blob === '') return null;
    $minLen = SILPHNET_EMAIL_NONCE_LEN + SILPHNET_EMAIL_TAG_LEN;
    if (strlen($blob) <= $minLen) return null;

    $key = silphnet_email_key();
    $nonce = substr($blob, 0, SILPHNET_EMAIL_NONCE_LEN);
    $tag = substr($blob, SILPHNET_EMAIL_NONCE_LEN, SILPHNET_EMAIL_TAG_LEN);
    $ciphertext = substr($blob, $minLen);

    $plaintext = openssl_decrypt(
        $ciphertext, SILPHNET_EMAIL_CIPHER, $key, OPENSSL_RAW_DATA,
        $nonce, $tag
    );
    return ($plaintext === false) ? null : $plaintext;
}

// EMAIL_ENCRYPTION_KEY (db.php) is a plain string secret, hex-decoded here
// into real key bytes - stored in db.php as a 64-character hex string
// (32 raw bytes = AES-256's real key size) rather than a raw binary
// constant, since a hex string is far less likely to get mangled by
// editors/copy-paste than raw bytes would be.
function silphnet_email_key() {
    if (!defined('EMAIL_ENCRYPTION_KEY') || EMAIL_ENCRYPTION_KEY === '' || EMAIL_ENCRYPTION_KEY === 'CHANGE-ME') {
        silphnet_error('server email encryption not configured', 500);
    }
    $key = @hex2bin(EMAIL_ENCRYPTION_KEY);
    if ($key === false || strlen($key) !== 32) {
        silphnet_error('server email encryption misconfigured (key must be 64 hex characters)', 500);
    }
    return $key;
}
