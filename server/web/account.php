<?php
// SilphNet - account management page. Log in with name+password (same
// credentials the mod itself uses), then view/edit your username and
// Trainer ID with live availability checking.
//
// This page itself does no direct DB work - it's a static shell whose
// JS calls the same login.php/check_name.php/check_trainer_id.php/
// update_account.php endpoints the mod (or any other client) could call.
// The session token this page gets back from login.php is held only in
// page memory (a JS variable), never localStorage/sessionStorage/cookies -
// closing or refreshing the tab requires logging in again, which is a
// deliberate simplicity/safety trade-off for a page whose only job is
// occasional account edits, not a persistent logged-in session.
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>My Account - SilphNet</title>
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
  .hint { font-size: 0.85rem; margin: -8px 0 14px; min-height: 1.2em; }
  .hint.ok { color: var(--green); }
  .hint.bad { color: var(--red); }
  .msg { font-size: 0.9rem; margin-top: 10px; min-height: 1.2em; }
  .msg.ok { color: var(--green); }
  .msg.bad { color: var(--red); }
  .hidden { display: none; }
  .trainer-id-display { font-size: 1.1rem; color: var(--blue); margin-bottom: 4px; }
</style>
</head>
<body>
<div class="wrap">
  <a class="back" href="index.php">&larr; back to SilphNet</a>
  <h1>My account</h1>

  <div id="loginCard" class="card">
    <label for="loginName">Name</label>
    <input type="text" id="loginName" maxlength="16" autocomplete="username">
    <label for="loginPass">Password</label>
    <input type="password" id="loginPass" autocomplete="current-password">
    <button id="loginBtn">Log in</button>
    <p id="loginMsg" class="msg"></p>
  </div>

  <div id="accountCard" class="card hidden">
    <p class="trainer-id-display">Trainer ID: <strong id="currentTrainerId">-----</strong></p>
    <p style="color: var(--text-dim); font-size: 0.9rem; margin-top: 0;">Logged in as <strong id="currentName">-</strong></p>

    <label for="newName">Change username</label>
    <input type="text" id="newName" maxlength="16">
    <p id="nameHint" class="hint"></p>

    <label for="newTrainerId">Change Trainer ID (0-65535)</label>
    <input type="text" id="newTrainerId" maxlength="5" inputmode="numeric">
    <p id="tidHint" class="hint"></p>

    <label for="confirmPass">Confirm with your password</label>
    <input type="password" id="confirmPass" autocomplete="current-password">

    <button id="saveBtn">Save changes</button>
    <p id="saveMsg" class="msg"></p>
  </div>
</div>

<script>
// API_BASE points at the /api subfolder, NOT the same directory this
// page is served from - account.php lives at the site ROOT (so it's
// reachable at yoursite.com/account.php), while every gameplay endpoint
// this page calls (login.php, check_name.php, check_trainer_id.php,
// update_account.php) lives one level down in /api/, kept deliberately
// separate from the public-facing site per direct request ("I was going
// to keep api just for the gaming mechanics side of things"). If you
// ever rename or relocate the api/ folder on your own hosting, this is
// the one line to change to match.
const API_BASE = '/api';

let token = null;
let accountId = null;
let currentName = '';
let currentTrainerId = '';
let nameAvailable = null; // null = not checked yet, true/false once known
let tidAvailable = null;

function el(id) { return document.getElementById(id); }

async function apiPost(path, params) {
  const body = new URLSearchParams(params);
  const res = await fetch(`${API_BASE}/${path}`, { method: 'POST', body });
  return res.json();
}

el('loginBtn').addEventListener('click', async () => {
  const name = el('loginName').value.trim();
  const password = el('loginPass').value;
  el('loginMsg').textContent = '';
  if (!name || !password) {
    el('loginMsg').textContent = 'Enter your name and password.';
    el('loginMsg').className = 'msg bad';
    return;
  }
  el('loginBtn').disabled = true;
  el('loginBtn').textContent = 'Logging in...';
  try {
    const data = await apiPost('login.php', { name, password });
    if (!data.ok) {
      el('loginMsg').textContent = data.error || 'Login failed.';
      el('loginMsg').className = 'msg bad';
      return;
    }
    token = data.token;
    accountId = data.account_id;
    currentName = name;
    currentTrainerId = data.trainer_id;
    el('currentName').textContent = currentName;
    el('currentTrainerId').textContent = currentTrainerId;
    el('newName').value = currentName;
    el('newTrainerId').value = currentTrainerId;
    el('loginCard').classList.add('hidden');
    el('accountCard').classList.remove('hidden');
  } catch (e) {
    el('loginMsg').textContent = 'Could not reach the server. Try again.';
    el('loginMsg').className = 'msg bad';
  } finally {
    el('loginBtn').disabled = false;
    el('loginBtn').textContent = 'Log in';
  }
});

// Debounced live-check helper - fires the given check function 400ms
// after the user stops typing, not on every keystroke, so this isn't
// hammering the server on every character.
function debounce(fn, delay) {
  let t = null;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), delay);
  };
}

const checkName = debounce(async () => {
  const name = el('newName').value.trim();
  if (name === currentName) {
    el('nameHint').textContent = 'This is your current name.';
    el('nameHint').className = 'hint ok';
    nameAvailable = true;
    return;
  }
  const data = await apiPost('check_name.php', { token, name });
  if (data.available) {
    el('nameHint').textContent = 'Available.';
    el('nameHint').className = 'hint ok';
    nameAvailable = true;
  } else {
    el('nameHint').textContent = data.reason || 'Not available.';
    el('nameHint').className = 'hint bad';
    nameAvailable = false;
  }
}, 400);

const checkTrainerId = debounce(async () => {
  const raw = el('newTrainerId').value.trim();
  if (raw === String(parseInt(currentTrainerId, 10))) {
    el('tidHint').textContent = 'This is your current Trainer ID.';
    el('tidHint').className = 'hint ok';
    tidAvailable = true;
    return;
  }
  const data = await apiPost('check_trainer_id.php', { token, trainer_id: raw });
  if (data.available) {
    el('tidHint').textContent = 'Available.';
    el('tidHint').className = 'hint ok';
    tidAvailable = true;
  } else {
    el('tidHint').textContent = data.reason || 'Not available.';
    el('tidHint').className = 'hint bad';
    tidAvailable = false;
  }
}, 400);

el('newName').addEventListener('input', () => {
  nameAvailable = null;
  el('nameHint').textContent = '';
  checkName();
});
el('newTrainerId').addEventListener('input', () => {
  // Digits only, capped at 5 characters - mirrors the mod's own D-pad
  // digit spinner range (5 digits, 00000-65535) rather than letting
  // someone type an arbitrary long number that update_account.php would
  // just reject anyway.
  el('newTrainerId').value = el('newTrainerId').value.replace(/\D/g, '').slice(0, 5);
  tidAvailable = null;
  el('tidHint').textContent = '';
  checkTrainerId();
});

el('saveBtn').addEventListener('click', async () => {
  const newName = el('newName').value.trim();
  const newTrainerId = el('newTrainerId').value.trim();
  const password = el('confirmPass').value;
  el('saveMsg').textContent = '';

  if (!password) {
    el('saveMsg').textContent = 'Enter your password to confirm.';
    el('saveMsg').className = 'msg bad';
    return;
  }
  // Client-side gate on the same nameAvailable/tidAvailable flags the
  // live-check hints already set - purely a UX nicety (don't let someone
  // click Save while a hint is still showing red). update_account.php
  // re-checks everything for real regardless of what this says, since a
  // race (someone else grabbing the name between the last check and this
  // click) is real and can't be caught client-side.
  if (nameAvailable === false) {
    el('saveMsg').textContent = 'Fix the username before saving.';
    el('saveMsg').className = 'msg bad';
    return;
  }
  if (tidAvailable === false) {
    el('saveMsg').textContent = 'Fix the Trainer ID before saving.';
    el('saveMsg').className = 'msg bad';
    return;
  }

  const params = { token, password };
  if (newName !== currentName) params.name = newName;
  if (newTrainerId !== String(parseInt(currentTrainerId, 10))) params.trainer_id = newTrainerId;

  if (!params.name && !params.trainer_id) {
    el('saveMsg').textContent = 'Nothing changed.';
    el('saveMsg').className = 'msg bad';
    return;
  }

  el('saveBtn').disabled = true;
  el('saveBtn').textContent = 'Saving...';
  try {
    const data = await apiPost('update_account.php', params);
    if (!data.ok) {
      el('saveMsg').textContent = data.error || 'Could not save changes.';
      el('saveMsg').className = 'msg bad';
      return;
    }
    currentName = data.name;
    currentTrainerId = data.trainer_id;
    el('currentName').textContent = currentName;
    el('currentTrainerId').textContent = currentTrainerId;
    el('confirmPass').value = '';
    el('saveMsg').textContent = 'Saved. Log in again in-game to see the change take effect.';
    el('saveMsg').className = 'msg ok';
  } catch (e) {
    el('saveMsg').textContent = 'Could not reach the server. Try again.';
    el('saveMsg').className = 'msg bad';
  } finally {
    el('saveBtn').disabled = false;
    el('saveBtn').textContent = 'Save changes';
  }
});
</script>
</body>
</html>
