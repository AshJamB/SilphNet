<?php
// SilphNet accounts - live availability check for a candidate username,
// used by account.php's rename form as the user types. Read-only (no
// writes) - the actual rename happens in update_account.php, which
// re-validates everything here again server-side rather than trusting
// this endpoint's answer, since a user could theoretically call
// update_account.php directly without ever hitting this one first.
//
// Token-gated like every other endpoint (see auth.php) - not because a
// stranger seeing "is NAME taken" is dangerous on its own, but so this
// can't be hit anonymously at scale from outside the mod/site as a free
// username-enumeration tool.
//
// POST: token, name
// Returns: {"ok":true,"available":true|false,"reason":"..."|null}
// "reason" is set (available:false) for a name that's just plain invalid
// (too long, bad characters) as well as one that's genuinely taken - the
// page shows the same "not available" state either way, just with the
// specific reason as helper text.

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();

$name = trim($_POST['name'] ?? '');

if ($name === '') {
    silphnet_json(['ok' => true, 'available' => false, 'reason' => 'enter a name']);
}
if (strlen($name) > 16) {
    silphnet_json(['ok' => true, 'available' => false, 'reason' => 'too long (max 16 characters)']);
}
// Same characters register.php has always rejected - kept identical
// here so a name that would pass this check but fail at actual rename
// time (or vice versa) can never happen.
if (preg_match('/[|;,\r\n]/', $name)) {
    silphnet_json(['ok' => true, 'available' => false, 'reason' => 'contains invalid characters']);
}

try {
    $pdo = silphnet_db();
    // Own current name doesn't count as "taken" - re-submitting the name
    // you already have (e.g. after backspacing and retyping it) should
    // read as available, not blocked by yourself.
    $stmt = $pdo->prepare('SELECT account_id FROM accounts WHERE name = :name AND account_id != :me');
    $stmt->execute([':name' => $name, ':me' => $account['account_id']]);
    if ($stmt->fetch()) {
        silphnet_json(['ok' => true, 'available' => false, 'reason' => 'that name is taken']);
    }
    silphnet_json(['ok' => true, 'available' => true, 'reason' => null]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
