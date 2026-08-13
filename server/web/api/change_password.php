<?php
// SilphNet accounts - change the caller's own password. Same security bar
// as update_account.php (rename/re-ID): a valid session token alone isn't
// enough, the CURRENT password must be re-verified here too, before a new
// one is set - a stolen/leaked session token on its own (e.g. a cached
// mod.save token on a shared device) can't be used to lock the real owner
// out by changing their password.
//
// POST: token, current_password, new_password
// Returns: {"ok":true}
//
// Every existing session for this account (including the one making this
// request) is left alone - changing your password doesn't need to log out
// every device, same as most real-world account systems; a compromised
// token being able to change the password would be the actual problem to
// fix, and re-checking current_password here already closes that.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();

$currentPassword = (string)($_POST['current_password'] ?? '');
$newPassword = (string)($_POST['new_password'] ?? '');

if ($currentPassword === '' || $newPassword === '') {
    silphnet_error('current_password and new_password are both required');
}
// Same floor as register.php's own password rule - kept identical so a
// password that would be rejected at signup can't be set later via this
// endpoint instead.
if (strlen($newPassword) < 4) {
    silphnet_error('new password must be at least 4 characters');
}

try {
    $pdo = silphnet_db();

    $stmt = $pdo->prepare('SELECT password_hash FROM accounts WHERE account_id = :id');
    $stmt->execute([':id' => $account['account_id']]);
    $row = $stmt->fetch();
    if (!$row || !password_verify($currentPassword, $row['password_hash'])) {
        silphnet_error('current password is incorrect', 401);
    }

    $newHash = password_hash($newPassword, PASSWORD_BCRYPT);
    $pdo->prepare('UPDATE accounts SET password_hash = :hash WHERE account_id = :id')
        ->execute([':hash' => $newHash, ':id' => $account['account_id']]);

    silphnet_json(['ok' => true]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
