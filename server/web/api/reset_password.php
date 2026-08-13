<?php
// SilphNet accounts - finish a password reset, given the token emailed by
// request_password_reset.php. Public endpoint (no session token - the
// reset token itself IS the proof of identity here, same role a session
// token plays elsewhere, just single-use and much shorter-lived).
//
// POST: token, new_password
// Returns: {"ok":true} on success, or a real error (this endpoint CAN be
// specific about what went wrong - "expired"/"already used"/"not found" -
// unlike request_password_reset.php, since by this point the caller
// already has a token that could only have come from a real email sent
// to a real address on file, so there's nothing left to enumerate.

require __DIR__ . '/db.php';

$token = trim($_POST['token'] ?? '');
$newPassword = (string)($_POST['new_password'] ?? '');

if ($token === '') silphnet_error('missing token');
if ($newPassword === '') silphnet_error('missing new_password');
// Same floor as register.php/change_password.php - kept identical so a
// password rejected everywhere else can't be set via this path instead.
if (strlen($newPassword) < 4) silphnet_error('new password must be at least 4 characters');

try {
    $pdo = silphnet_db();
    $pdo->beginTransaction();

    // FOR UPDATE - locks this row for the duration of the transaction, so
    // two near-simultaneous uses of the exact same token (e.g. an email
    // client "link preview" prefetch racing the real click) can't both
    // pass the used_at/expiry check before either one writes used_at.
    // expired is computed in the SAME query, in SQL rather than PHP - see
    // auth.php's silphnet_require_token() for why (sidesteps any
    // PHP-vs-MySQL timezone mismatch entirely) - so there's no need for a
    // second query (and no second query means no second, unlocked read
    // that could see a different row state than the locked one above).
    $stmt = $pdo->prepare(
        'SELECT account_id, used_at, (expires_at < NOW()) AS expired
         FROM password_resets WHERE token = :token FOR UPDATE'
    );
    $stmt->execute([':token' => $token]);
    $row = $stmt->fetch();

    if (!$row) {
        $pdo->rollBack();
        silphnet_error('reset link not recognised', 401);
    }
    if ($row['used_at'] !== null) {
        $pdo->rollBack();
        silphnet_error('this reset link has already been used', 401);
    }
    if ((int)$row['expired'] === 1) {
        $pdo->rollBack();
        silphnet_error('this reset link has expired - request a new one', 401);
    }

    $newHash = password_hash($newPassword, PASSWORD_BCRYPT);
    $pdo->prepare('UPDATE accounts SET password_hash = :hash WHERE account_id = :id')
        ->execute([':hash' => $newHash, ':id' => $row['account_id']]);

    $pdo->prepare('UPDATE password_resets SET used_at = NOW() WHERE token = :token')
        ->execute([':token' => $token]);

    $pdo->commit();
    silphnet_json(['ok' => true]);
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack();
    silphnet_error('db error', 500);
}
