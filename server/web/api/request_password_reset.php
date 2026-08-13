<?php
// SilphNet accounts - start a password reset. Public endpoint (no token -
// the whole point is the caller is logged OUT and can't prove who they
// are yet), so this has to be careful not to leak anything through its
// response or timing.
//
// POST: name
// Returns: {"ok":true} ALWAYS, regardless of whether the name exists, has
// no recovery email set, or the mail send itself fails - deliberately the
// exact same response in every case, so this endpoint can't be used to
// enumerate which usernames exist or which accounts have an email on
// file. The real user finds out what happened by checking their inbox
// (or not receiving anything, if nothing was on file to send to) - not
// from this response.

require __DIR__ . '/db.php';
require __DIR__ . '/email_crypto.php';
require __DIR__ . '/mailer.php';

// A reset link is valid for this long after being requested - short
// enough that a genuinely stale/leaked link (e.g. sitting unread in an
// old email for months) can't be used, long enough that a real user
// checking their email a bit later that same day isn't caught out.
const SILPHNET_RESET_TOKEN_TTL_MINUTES = 60;

$name = trim($_POST['name'] ?? '');
if ($name === '') silphnet_error('missing name');

// Every path below ends in the exact same silphnet_json(['ok' => true])
// with nothing else in the response - see the comment above for why.
try {
    $pdo = silphnet_db();

    $stmt = $pdo->prepare('SELECT account_id, email FROM accounts WHERE name = :name');
    $stmt->execute([':name' => $name]);
    $row = $stmt->fetch();

    if ($row && $row['email'] !== null) {
        $email = silphnet_decrypt_email($row['email']);
        if ($email !== null) {
            $token = bin2hex(random_bytes(32));
            $pdo->prepare(
                'INSERT INTO password_resets (token, account_id, created_at, expires_at)
                 VALUES (:token, :id, NOW(), NOW() + INTERVAL ' . SILPHNET_RESET_TOKEN_TTL_MINUTES . ' MINUTE)'
            )->execute([':token' => $token, ':id' => $row['account_id']]);

            // account.php itself handles ?reset=<token> as a distinct page
            // state (see its own JS) - this link just needs to land back
            // on that same page with the token in the query string.
            $resetUrl = 'https://silphnet.jamshark.co.uk/account.php?reset=' . $token;
            $body = "Someone (hopefully you) requested a SilphNet password reset for the account \"$name\".\n\n"
                  . "Click this link to set a new password - it expires in " . SILPHNET_RESET_TOKEN_TTL_MINUTES . " minutes:\n"
                  . "$resetUrl\n\n"
                  . "If you didn't request this, you can safely ignore this email - your password hasn't been changed.";
            silphnet_send_mail($email, 'SilphNet password reset', $body);
        }
    }

    silphnet_json(['ok' => true]);
} catch (PDOException $e) {
    // Even a DB error doesn't get its own distinct response here - still
    // just {"ok":true}, for the same enumeration-safety reason as above.
    // (Genuinely unexpected DB failures are still visible server-side via
    // PHP's normal error log, just not surfaced to the caller.)
    error_log('SilphNet request_password_reset: db error - ' . $e->getMessage());
    silphnet_json(['ok' => true]);
}
