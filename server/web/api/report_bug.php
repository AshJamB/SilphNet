<?php
// SilphNet - PUBLIC, unauthenticated "Report a bug" form (a hero button
// on the homepage). Deliberately takes NO reporter-identifying field at
// all (no name, no email) - GitHub issues on this repo are visible to
// everyone with access to it, and this project has no actual follow-up
// process that would ever use a reporter's contact info anyway, so
// asking for one would only ever create a real exposure (a real email
// address landing in an issue, exactly what happened during testing)
// for zero practical benefit. If a reporter wants to be contacted back,
// they can say so and how in the description itself, at their own
// discretion - the form itself never invites it.
// Deliberately open to anyone, logged in or not - a bug is just as real
// (and just as useful to hear about) from someone who hasn't made a
// SilphNet account, or is reporting from a browser with no game session
// at all, as it is from an existing player. Requiring login here would
// only ever block genuine reports, not stop abuse - see the honeypot/
// rate-limit design below for what actually guards against that.
//
// On success, files a REAL issue in the private AshJamB/SilphNet GitHub
// repo via GitHub's REST API (POST /repos/{owner}/{repo}/issues), using a
// fine-grained personal access token scoped to just this repo's Issues
// permission (GITHUB_BUG_REPORT_TOKEN in db.php - see db.php.example's
// own comment on why a fine-grained, single-repo token, not a classic
// "repo"-scoped one). Fails soft with a clear error if that token is
// still the CHANGE-ME placeholder, same convention the recovery-email
// feature already uses for its own optional config.
//
// Anti-abuse, kept deliberately simple for a small community project
// (see the design discussion this shipped with - a full account-login
// requirement was considered and rejected as pure friction for genuine
// reports with no matching abuse benefit):
//   1. Honeypot - a "website" field that's invisible/unreachable to a
//      real visitor (see index.php's CSS) but that simple bots fill in
//      automatically. Non-empty -> silently return success without
//      touching the database or GitHub at all, so a bot gets no signal
//      that it was caught.
//   2. Per-IP rate limit - one accepted report per
//      SILPHNET_BUG_REPORT_COOLDOWN_MINUTES, tracked in the bug_reports
//      table (ip_hash only, never the raw IP - see schema.sql's own
//      comment on that column). Checked BEFORE calling GitHub at all, so
//      a burst of submissions from one IP can only ever create one real
//      issue per cooldown window.
//
// POST: title, description, [website (honeypot, must stay empty)]
// Returns: {"ok":true,"issue_url":"https://github.com/..."}
//          (or {"ok":true} for a honeypot-tripped submission, indistinguishable
//          from a real success on purpose)

require __DIR__ . '/db.php';

const SILPHNET_BUG_REPORT_COOLDOWN_MINUTES = 5;
const SILPHNET_BUG_TITLE_MAX = 100;
const SILPHNET_BUG_BODY_MAX = 2000;

// Honeypot tripped - a real visitor never sees or fills this field (see
// index.php), so anything here means an automated submission. Return the
// exact same success shape a genuine report gets, so there's no signal
// telling the bot its submission was discarded rather than accepted.
if (trim($_POST['website'] ?? '') !== '') {
    silphnet_json(['ok' => true]);
}

$title = trim($_POST['title'] ?? '');
$description = trim($_POST['description'] ?? '');

if ($title === '' || $description === '') {
    silphnet_error('title and description are both required');
}
$title = substr($title, 0, SILPHNET_BUG_TITLE_MAX);
$description = substr($description, 0, SILPHNET_BUG_BODY_MAX);

if (!defined('GITHUB_BUG_REPORT_TOKEN') || GITHUB_BUG_REPORT_TOKEN === 'CHANGE-ME') {
    silphnet_error('Bug reporting is not configured yet - GITHUB_BUG_REPORT_TOKEN is still the placeholder value in db.php.', 500);
}

try {
    $pdo = silphnet_db();

    // SHA-256, not the raw IP - see schema.sql's own comment on this
    // column for why. REMOTE_ADDR (not any X-Forwarded-For style header)
    // deliberately - this project doesn't run behind a proxy/load
    // balancer that would make REMOTE_ADDR wrong, and a spoofable header
    // would defeat the entire point of a rate limit.
    $ipHash = hash('sha256', $_SERVER['REMOTE_ADDR'] ?? 'unknown');

    $stmt = $pdo->prepare(
        'SELECT COUNT(*) AS c FROM bug_reports
         WHERE ip_hash = :ip_hash AND created_at >= NOW() - INTERVAL ' . SILPHNET_BUG_REPORT_COOLDOWN_MINUTES . ' MINUTE'
    );
    $stmt->execute([':ip_hash' => $ipHash]);
    if ((int)$stmt->fetch()['c'] > 0) {
        silphnet_error('Please wait a few minutes before submitting another bug report.', 429);
    }

    $bodyLines = [$description, '', '---', 'Submitted via the SilphNet website bug report form.'];

    $issuePayload = json_encode([
        'title' => "[Bug report] $title",
        'body' => implode("\n", $bodyLines),
        'labels' => ['bug', 'user-reported'],
    ]);

    // Same file_get_contents + stream_context approach index.php's own
    // silphnet_github_get() uses for the read-only repo/release cards -
    // no curl dependency, consistent with the rest of this project. This
    // one POSTs and carries a real auth token, unlike that read-only
    // helper, so it's kept separate rather than generalized to cover both.
    $ctx = stream_context_create(['http' => [
        'method' => 'POST',
        'header' =>
            "User-Agent: SilphNet-Bug-Report\r\n" .
            "Accept: application/vnd.github+json\r\n" .
            "Authorization: Bearer " . GITHUB_BUG_REPORT_TOKEN . "\r\n" .
            "Content-Type: application/json\r\n",
        'content' => $issuePayload,
        'timeout' => 10,
        'ignore_errors' => true,
    ]]);
    $repo = defined('GITHUB_BUG_REPORT_REPO') ? GITHUB_BUG_REPORT_REPO : 'AshJamB/SilphNet';
    $responseBody = @file_get_contents("https://api.github.com/repos/$repo/issues", false, $ctx);
    $statusLine = $http_response_header[0] ?? '';
    $statusOk = (bool)preg_match('#HTTP/\S+\s+201#', $statusLine);

    if (!$statusOk || $responseBody === false) {
        // GitHub genuinely unreachable/misconfigured (bad token, wrong
        // repo, rate-limited, etc) - fails soft with a generic message
        // rather than relaying GitHub's own raw error text to a public,
        // unauthenticated caller.
        silphnet_error('Could not file the bug report right now. Please try again later.', 502);
    }

    // Only record the attempt in the rate-limit ledger on genuine
    // success - a failed GitHub call (their outage, not the reporter's
    // fault) shouldn't cost the reporter their one submission for this
    // cooldown window.
    $stmt = $pdo->prepare('INSERT INTO bug_reports (ip_hash, created_at) VALUES (:ip_hash, NOW())');
    $stmt->execute([':ip_hash' => $ipHash]);

    $issueData = json_decode($responseBody, true);
    silphnet_json(['ok' => true, 'issue_url' => $issueData['html_url'] ?? null]);
} catch (PDOException $e) {
    silphnet_error('db error', 500);
}
