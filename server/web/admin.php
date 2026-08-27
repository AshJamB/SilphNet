<?php
// SilphNet - admin recovery tool. One job: let Ash generate a password
// reset link for a friend who has no recovery email on file (the one
// situation account.php's own "Forgot your password?" flow genuinely
// cannot help with - see account.php's forgotCard copy). Not linked from
// anywhere on the public site (index.php, account.php) - reachable only
// by knowing this exact URL, same "security by not advertising it" this
// page's own admin key backs up with a real check server-side
// (admin_reset_password.php refuses to run at all without the correct
// key, so this isn't the ONLY thing standing between a stranger and
// resetting someone's password - just the first layer).
//
// The admin key is held only in page memory (a JS variable), exactly like
// account.php's session token - never localStorage/sessionStorage/a
// cookie, so there's nothing on disk in the browser for someone else
// using this computer later to find.
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Admin - SilphNet</title>
<!-- noindex, nofollow - unlike account.php (noindex, follow), this page
     has no outgoing link worth counting and no reason to ever appear in
     search results or be crawled from anywhere that does link to it. -->
<meta name="robots" content="noindex, nofollow">
<link rel="canonical" href="https://silphnet.jamshark.co.uk/admin.php">
<link rel="icon" type="image/x-icon" href="assets/favicon.ico">
<style>
  :root {
    --bg: #0b0e14;
    --panel: #12161f;
    --panel-border: #262c3a;
    --orange: #f6a935;
    --orange-dark: #c97e1c;
    --blue: #4fc3f7;
    --red: #e05a5a;
    --green: #5ad18a;
    --text: #e8ecf4;
    --text-dim: #9aa4b8;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.6;
  }
  .wrap { max-width: 480px; margin: 0 auto; padding: 32px 20px 64px; }
  a.back { color: var(--text-dim); text-decoration: none; font-size: 0.9rem; }
  a.back:hover { color: var(--blue); }
  h1 { font-size: 1.4rem; color: var(--orange); margin: 20px 0; }
  .card {
    background: var(--panel); border: 1px solid var(--panel-border); border-radius: 12px;
    padding: 24px; margin-bottom: 20px;
  }
  label { display: block; font-size: 0.85rem; color: var(--text-dim); margin-bottom: 6px; }
  input[type=text], input[type=password] {
    width: 100%; padding: 10px 12px; margin-bottom: 14px; border-radius: 8px;
    border: 1px solid var(--panel-border); background: #1c2230; color: var(--text); font-size: 1rem;
  }
  input:focus { outline: none; border-color: var(--blue); }
  button {
    width: 100%; padding: 12px; border-radius: 8px; border: none; font-weight: 600;
    font-size: 1rem; cursor: pointer; background: var(--orange); color: #1a1200;
  }
  button:hover { background: var(--orange-dark); }
  button:disabled { background: var(--panel-border); color: var(--text-dim); cursor: not-allowed; }
  .msg { font-size: 0.9rem; margin-top: 10px; min-height: 1.2em; word-break: break-word; }
  .msg.ok { color: var(--green); }
  .msg.bad { color: var(--red); }
  .hidden { display: none; }
  .result-url {
    width: 100%; padding: 10px 12px; margin-top: 8px; border-radius: 8px;
    border: 1px solid var(--green); background: #1c2230; color: var(--text);
    font-size: 0.85rem; font-family: monospace;
  }
</style>
</head>
<body>
<div class="wrap">
  <a class="back" href="index.php">&larr; back to SilphNet</a>
  <h1>Admin - password recovery</h1>

  <div class="card">
    <p style="font-size: 0.85rem; color: var(--text-dim); margin-top: 0;">
      For a friend with no recovery email on file who's forgotten their password. Leave the email
      field blank to just get a one-time reset link back here, which you send them yourself
      (Discord, whatever). Fill it in and this ALSO saves that address as the account's real
      recovery email and sends the reset link there directly - so this is the one time you need to
      help, and every password they forget after this one, they can reset themselves with the
      normal "Forgot your password?" link, no admin needed. Either way the link expires in 24 hours
      and only works once. This does nothing unless ADMIN_KEY is set for real in db.php on the
      server.
    </p>
    <label for="adminKey">Admin key</label>
    <input type="password" id="adminKey" autocomplete="off">
    <label for="targetName">Account name</label>
    <input type="text" id="targetName" maxlength="16" autocomplete="off">
    <label for="targetEmail">Their email (optional - registers it and sends the link there)</label>
    <input type="text" id="targetEmail" autocomplete="off">
    <button id="genBtn">Generate reset link</button>
    <p id="genMsg" class="msg"></p>
    <input type="text" id="resultUrl" class="result-url hidden" readonly onclick="this.select()">
  </div>
</div>

<script>
const API_BASE = '/api';
function el(id) { return document.getElementById(id); }

el('genBtn').addEventListener('click', async () => {
  const adminKey = el('adminKey').value;
  const name = el('targetName').value.trim();
  const email = el('targetEmail').value.trim();
  el('genMsg').textContent = '';
  el('resultUrl').classList.add('hidden');

  if (!adminKey || !name) {
    el('genMsg').textContent = 'Enter the admin key and the account name.';
    el('genMsg').className = 'msg bad';
    return;
  }

  el('genBtn').disabled = true;
  el('genBtn').textContent = 'Generating...';
  try {
    const params = { admin_key: adminKey, name };
    if (email) params.email = email;
    const body = new URLSearchParams(params);
    const res = await fetch(`${API_BASE}/admin_reset_password.php`, { method: 'POST', body });
    const data = await res.json();
    if (!data.ok) {
      el('genMsg').textContent = data.error || 'Could not generate a reset link.';
      el('genMsg').className = 'msg bad';
      return;
    }
    // Three real outcomes to tell apart, not just "success" - email_set
    // is false for the plain manual-relay path (nothing changed on the
    // account, always show the link to send yourself); email_set true
    // splits further into "actually sent" vs "saved but the send itself
    // failed" (bad address, SMTP hiccup) - that second case still needs
    // the link shown as a fallback, same as the plain manual path, just
    // with a clear heads-up that the automatic email didn't go out.
    const hours = Math.round(data.expires_in_minutes / 60);
    if (!data.email_set) {
      el('genMsg').textContent =
        `Link for ${data.name}, expires in ${hours}h - send it to them, they open it and set a ` +
        `new password, then update MY NAME/PASSWORD in the mod's Options menu to match.`;
    } else if (data.email_sent) {
      el('genMsg').textContent =
        `Saved that email to ${data.name}'s account and sent the reset link there directly - ` +
        `expires in ${hours}h. They can use "Forgot your password?" themselves from now on. ` +
        `Link also shown below in case the email doesn't arrive.`;
    } else {
      el('genMsg').textContent =
        `Saved that email to ${data.name}'s account, but sending the email itself failed - check ` +
        `the SMTP settings in db.php, or just send this link to them yourself for now (expires in ` +
        `${hours}h). "Forgot your password?" will work for them going forward either way, once ` +
        `email sending is working.`;
    }
    el('genMsg').className = 'msg ok';
    el('resultUrl').value = data.reset_url;
    el('resultUrl').classList.remove('hidden');
  } catch (e) {
    el('genMsg').textContent = 'Could not reach the server. Try again.';
    el('genMsg').className = 'msg bad';
  } finally {
    el('genBtn').disabled = false;
    el('genBtn').textContent = 'Generate reset link';
  }
});
</script>
</body>
</html>
