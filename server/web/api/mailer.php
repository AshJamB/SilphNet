<?php
// SilphNet - thin wrapper around the vendored PHPMailer library
// (vendor/phpmailer/), configured from SMTP_* constants in db.php.
//
// PHPMailer is vendored directly (its 3 real source files, copied as-is
// from the official github.com/PHPMailer/PHPMailer release) rather than
// pulled in via composer - Verpex/cPanel shared hosting access varies
// (SSH/composer isn't guaranteed), but plain file upload always works, so
// this keeps deployment as simple as every other endpoint in this project:
// upload the .php files, nothing else to install.
//
// SMTP_HOST/PORT/USER/PASS/FROM_ADDRESS/FROM_NAME are all defined in
// db.php (gitignored, real values live only on the server) - see
// db.php.example for the placeholder template and comments on where to
// get real values once an email account + SMTP access exists.

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/vendor/phpmailer/Exception.php';
require_once __DIR__ . '/vendor/phpmailer/PHPMailer.php';
require_once __DIR__ . '/vendor/phpmailer/SMTP.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as PHPMailerException;

// Sends a plain-text email. Returns true on success, false on any failure
// (bad SMTP credentials, unreachable host, rejected recipient, etc.) -
// never throws, so a mail failure can be handled by the caller as a soft
// error rather than a fatal one (e.g. request_password_reset.php still
// wants to return its same generic "if that email is on file..." message
// either way, so a failure here shouldn't itself leak information about
// which case happened).
function silphnet_send_mail($toAddress, $subject, $body) {
    if (!defined('SMTP_HOST') || SMTP_HOST === '' || SMTP_HOST === 'CHANGE-ME') {
        // Not configured yet - fail soft rather than fatal, same reasoning
        // as above. Logged server-side (PHP's own error log) so this is
        // debuggable without exposing anything to the caller.
        error_log('SilphNet mailer: SMTP_HOST not configured, cannot send mail');
        return false;
    }

    $mail = new PHPMailer(true);
    try {
        $mail->isSMTP();
        $mail->Host = SMTP_HOST;
        $mail->Port = defined('SMTP_PORT') ? SMTP_PORT : 587;
        $mail->SMTPAuth = true;
        $mail->Username = defined('SMTP_USER') ? SMTP_USER : '';
        $mail->Password = defined('SMTP_PASS') ? SMTP_PASS : '';
        // STARTTLS on 587 is the common modern default; SMTPS (implicit
        // TLS) on 465 is the other realistic option - SMTP_SECURE lets
        // db.php pick whichever the actual mailbox provider requires
        // rather than this file guessing.
        $mail->SMTPSecure = defined('SMTP_SECURE') ? SMTP_SECURE : PHPMailer::ENCRYPTION_STARTTLS;

        $fromAddress = defined('SMTP_FROM_ADDRESS') ? SMTP_FROM_ADDRESS : SMTP_USER;
        $fromName = defined('SMTP_FROM_NAME') ? SMTP_FROM_NAME : 'SilphNet';
        $mail->setFrom($fromAddress, $fromName);
        $mail->addAddress($toAddress);

        $mail->isHTML(false);
        $mail->Subject = $subject;
        $mail->Body = $body;

        $mail->send();
        return true;
    } catch (PHPMailerException $e) {
        error_log('SilphNet mailer: send failed - ' . $mail->ErrorInfo);
        return false;
    }
}
