<?php
// SilphNet accounts - add or change the caller's own recovery email.
// Held to the same security bar as update_account.php/change_password.php:
// a valid session token alone isn't enough, the password is re-checked
// here too - a stolen/leaked session token can't be used to redirect
// where password-reset links get sent, which would otherwise be a way to
// fully take over an account without ever knowing its real password.
//
// POST: token, password, email
// Returns: {"ok":true,"email":"..."} - the email actually stored, echoed
// back so the calling page can confirm what was saved without needing a
// separate "get my current email" endpoint (that endpoint doesn't exist
// at all - see the comment above the email column in schema.sql for why
// giving that out isn't done lightly; account.php's own JS just remembers
// what it sent).
//
// email is genuinely optional account-wide (most accounts have none) -
// this endpoint is the ONLY way to set one, since in-game registration
// never asks for it.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';
require __DIR__ . '/email_crypto.php';

$account = silphnet_require_token();

$password = (string)($_POST['password'] ?? '');
if ($password === '') silphnet_error('password required to change account details', 401);

$email = trim($_POST['email'] ?? '');
if ($email === '') silphnet_error('email is required');
if (strlen($email) > 255) silphnet_error('email too long');
// A real (if intentionally loose) shape check - not exhaustive RFC 5322
// validation, just enough to catch an obvious typo before it's encrypted
// and stored, since a bounced reset email later is a worse failure mode
// than rejecting a clearly-wrong address now.
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    silphnet_error('that does not look like a valid email address');
}

try {
    $pdo = silphnet_db();

    $stmt = $pdo->prepare('SELECT password_hash FROM accounts WHERE account_id = :id');
    $stmt->execute([':id' => $account['account_id']]);
    $row = $stmt->fetch();
    if (!$row || !password_verify($password, $row['password_hash'])) {
        silphnet_error('wrong password', 401);
    }

    $encrypted = silphnet_encrypt_email($email);
    if ($encrypted === null) silphnet_error('could not save email', 500);

    $pdo->prepare('UPDATE accounts SET email = :email WHERE account_id = :id')
        ->execute([':email' => $encrypted, ':id' => $account['account_id']]);

    silphnet_json(['ok' => true, 'email' => $email]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
