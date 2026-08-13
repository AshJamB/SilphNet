<?php
// SilphNet accounts - live availability check for a candidate Trainer ID,
// used by account.php's Trainer ID picker as the user types. Read-only,
// same reasoning as check_name.php - update_account.php re-validates
// everything here again rather than trusting this endpoint's answer.
//
// POST: token, trainer_id (as a string of digits, e.g. "04815" or "4815" -
// both accepted, compared numerically)
// Returns: {"ok":true,"available":true|false,"reason":"..."|null}

require __DIR__ . '/db.php';
require __DIR__ . '/auth.php';

$account = silphnet_require_token();

$raw = trim($_POST['trainer_id'] ?? '');

if ($raw === '' || !ctype_digit($raw)) {
    silphnet_json(['ok' => true, 'available' => false, 'reason' => 'enter a number']);
}

$trainerId = (int)$raw;
// 0-65535 - same 16-bit range register.php's random_int(0, 65535) already
// assigns from, so a picked ID can never be a value the game itself
// wouldn't produce.
if ($trainerId < 0 || $trainerId > 65535) {
    silphnet_json(['ok' => true, 'available' => false, 'reason' => 'must be 0-65535']);
}

try {
    $pdo = silphnet_db();
    // Own current trainer_id doesn't count as "taken" - same reasoning
    // as check_name.php's account_id != :me guard.
    $stmt = $pdo->prepare('SELECT account_id FROM accounts WHERE trainer_id = :tid AND account_id != :me');
    $stmt->execute([':tid' => $trainerId, ':me' => $account['account_id']]);
    if ($stmt->fetch()) {
        silphnet_json(['ok' => true, 'available' => false, 'reason' => 'that ID is taken']);
    }
    silphnet_json(['ok' => true, 'available' => true, 'reason' => null]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
