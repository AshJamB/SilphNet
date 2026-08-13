<?php
// SilphNet async presence - shared DB connection.
// -----------------------------------------------------------------------
// Fill in DB_USER / DB_PASS below with the cPanel MySQL user you just
// created (jamshark_silphnet / the generated password). Never commit the
// real password to git - this file should be in .gitignore, or at minimum
// DB_PASS should be edited directly on the server, not in the repo copy.
// -----------------------------------------------------------------------

define('DB_HOST', 'localhost');
define('DB_NAME', 'jamshark_silphnet');
define('DB_USER', 'jamshark_silphnet');   // << EDIT ME if you used a different username
define('DB_PASS', 'CHANGE-ME');           // << EDIT ME - set on the server only, never in git

function silphnet_db() {
    static $pdo = null;
    if ($pdo === null) {
        $dsn = 'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4';
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
    }
    return $pdo;
}

// Every endpoint returns JSON, plain text errors included - never HTML
// error pages, so the mod's JSON-ish parsing never has to guess.
function silphnet_json($data, $code = 200) {
    http_response_code($code);
    header('Content-Type: application/json');
    echo json_encode($data);
    exit;
}

function silphnet_error($msg, $code = 400) {
    silphnet_json(['ok' => false, 'error' => $msg], $code);
}
