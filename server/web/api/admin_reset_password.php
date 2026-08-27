<?php
// SilphNet - admin-triggered password reset. For the exact gap the normal
// forgot-password flow can't cover: an account with no recovery email on
// file (set_email.php is entirely optional, and the mod itself never
// prompts for one - only account.php does) has NO self-serve way back in
// if the owner forgets their password. Confirmed as a real, reported case
// (a friend on a Gen 2 save with no email set, locked out). Rather than
// Ash hand-running an UPDATE against password_hash directly (works, but
// error-prone, and bypasses every safeguard reset_password.php already
// has - expiry, single-use, transaction locking), this generates a REAL
// row in the exact same password_resets table request_password_reset.php
// uses, so the friend finishes on the exact same "set a new password"
// screen (account.php?reset=<token>) a normal email link would have sent
// them to. reset_password.php itself needs no changes at all to support
// this - a token is a token, regardless of which path created it.
//
// POST: admin_key, name, [email]
// Returns (no email given): {"ok":true,"name":"...","reset_url":"...",
//   "expires_in_minutes":N,"email_set":false,"email_sent":false}
// Returns (email given):    {"ok":true,"name":"...","reset_url":"...",
//   "expires_in_minutes":N,"email_set":true,"email_sent":true|false}
//
// Two ways to get the account holder back in, both available every call:
//
//   1. Manual relay (email omitted) - generates the link only. You copy
//      reset_url yourself into Discord/whatever. Nothing about the account
//      changes - no email gets stored anywhere.
//
//   2. Register + email (email given) - this is the real answer to "is
//      there a self-service option": there genuinely isn't one for an
//      account that has never proven ownership of an email or set up any
//      other recovery secret (a Trainer ID doesn't count - it's meant to
//      be handed out to add friends, so it can never double as a proof of
//      identity). What this DOES do is turn a one-time admin favour into a
//      permanently self-service account from here on: the email you were
//      told (over Discord, in person, wherever - the identity check here
//      is still fundamentally "you trust the person who told you this
//      address, the same way you'd trust them asking you directly")
//      gets saved to accounts.email as their real recovery email via the
//      exact same silphnet_encrypt_email() set_email.php itself uses, and
//      a real reset email goes out via mailer.php. That account can use
//      the normal "Forgot your password?" flow on its own, unassisted,
//      for every password they ever forget after this one.
//
// reset_url is always returned alongside an email send, even when
// email_sent is true - a real fallback for you to relay by hand if the
// send itself silently fails (wrong address typo, SMTP hiccup, spam
// filter) rather than the account holder being stuck with nothing.
//
// Deliberately NOT the same "always return ok:true, never say what went
// wrong" enumeration-safety rule request_password_reset.php follows - that
// rule exists because THAT endpoint is reachable by anyone, logged out,
// with nothing to prove who they are. This one is useless without the
// real admin_key already, so a specific "no such account" error here only
// ever helps the one person who could reach this endpoint at all: you.
//
// admin_key is checked with hash_equals (constant-time - a plain === here
// would let a timing attack narrow down the real key one byte at a time,
// the same reasoning auth.php's own token checks already follow) and,
// unlike every optional CHANGE-ME setting in db.php.example, this one
// fails CLOSED - a still-default ADMIN_KEY makes this endpoint refuse to
// run at all, rather than silently accepting the literal string
// "CHANGE-ME" as a working admin key forever if you forget to set a real
// one.
//
// Deliberately does NOT re-check the account's own password the way
// set_email.php does before changing an email (that check exists there to
// stop a stolen SESSION TOKEN from redirecting recovery mail without
// knowing the real password) - here, admin_key standing in for the
// account holder's own authorization is the entire point of this
// endpoint, the same as every other admin_key-gated action above it.

require __DIR__ . '/db.php';
require __DIR__ . '/email_crypto.php';
require __DIR__ . '/mailer.php';

// Longer than the email flow's 60 minutes (request_password_reset.php) -
// this link has a human relay step in the middle (you copying it into a
// Discord message, or the account holder waiting on an email you asked to
// be sent), which a short-lived link tuned for "click it right out of your
// own inbox" would routinely miss.
const SILPHNET_ADMIN_RESET_TOKEN_TTL_MINUTES = 1440;

if (!defined('ADMIN_KEY') || ADMIN_KEY === '' || ADMIN_KEY === 'CHANGE-ME') {
    silphnet_error('admin recovery is not configured on this server yet', 503);
}

$adminKey = (string)($_POST['admin_key'] ?? '');
$name = trim($_POST['name'] ?? '');
$email = trim($_POST['email'] ?? '');

if ($adminKey === '' || !hash_equals(ADMIN_KEY, $adminKey)) {
    // Same generic 401 either way (missing vs wrong) - no reason to tell
    // an incorrect caller which of the two problems they have.
    silphnet_error('invalid admin key', 401);
}
if ($name === '') silphnet_error('missing name');

// Same loose-but-real shape check set_email.php uses - not exhaustive
// RFC 5322 validation, just enough to catch an obvious typo before it's
// encrypted and stored, since a bounced reset email later is a worse
// failure mode than rejecting a clearly-wrong address now. Only checked
// at all when an email was actually given - omitting it entirely stays
// the plain manual-relay path with no validation to fail.
if ($email !== '') {
    if (strlen($email) > 255) silphnet_error('email too long');
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        silphnet_error('that does not look like a valid email address');
    }
}

try {
    $pdo = silphnet_db();

    $stmt = $pdo->prepare('SELECT account_id FROM accounts WHERE name = :name');
    $stmt->execute([':name' => $name]);
    $row = $stmt->fetch();
    if (!$row) silphnet_error('no account with that name', 404);

    $emailSet = false;
    if ($email !== '') {
        $encrypted = silphnet_encrypt_email($email);
        if ($encrypted === null) silphnet_error('could not save email', 500);
        $pdo->prepare('UPDATE accounts SET email = :email WHERE account_id = :id')
            ->execute([':email' => $encrypted, ':id' => $row['account_id']]);
        $emailSet = true;
    }

    $token = bin2hex(random_bytes(32));
    $pdo->prepare(
        'INSERT INTO password_resets (token, account_id, created_at, expires_at)
         VALUES (:token, :id, NOW(), NOW() + INTERVAL ' . SILPHNET_ADMIN_RESET_TOKEN_TTL_MINUTES . ' MINUTE)'
    )->execute([':token' => $token, ':id' => $row['account_id']]);

    // Same account.php?reset=<token> URL shape request_password_reset.php's
    // own emailed link uses - account.php's JS doesn't know or care which
    // path generated the token, only reset_password.php ever validates it.
    $resetUrl = 'https://silphnet.jamshark.co.uk/account.php?reset=' . $token;

    $emailSent = false;
    if ($emailSet) {
        $body = "An admin registered this email as the SilphNet recovery address for the account \"$name\" "
              . "and requested a password reset on your behalf.\n\n"
              . "Click this link to set a new password - it expires in "
              . round(SILPHNET_ADMIN_RESET_TOKEN_TTL_MINUTES / 60) . " hours:\n"
              . "$resetUrl\n\n"
              . "From now on, you can use the \"Forgot your password?\" link on the SilphNet account "
              . "page yourself any time, without needing an admin's help - this email address is now "
              . "saved as your account's recovery email.\n\n"
              . "If you weren't expecting this, let whoever administers your SilphNet server know.";
        $emailSent = silphnet_send_mail($email, 'SilphNet password reset', $body);
    }

    silphnet_json([
        'ok' => true,
        'name' => $name,
        'reset_url' => $resetUrl,
        'expires_in_minutes' => SILPHNET_ADMIN_RESET_TOKEN_TTL_MINUTES,
        'email_set' => $emailSet,
        'email_sent' => $emailSent,
    ]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
