<?php
// SilphNet - public landing page. Pure presentation, no auth, no writes -
// the only "dynamic" part is the optional GitHub release card below,
// which degrades gracefully to a static link if the API call fails (e.g.
// while the repo is still private - api.github.com returns nothing for a
// private repo without an auth token, and this project deliberately
// avoids embedding a GitHub token in a publicly-hosted PHP file just to
// show a version number). The moment the repo goes public, this starts
// showing live data with no further changes needed here.

// 5-second timeout so a slow/unreachable GitHub API can never hang this
// page - if it fails or times out, $ghRelease/$ghRepo stay null and the
// card below just shows the static fallback.
function silphnet_github_get($url) {
    $ctx = stream_context_create(['http' => [
        'method' => 'GET',
        'header' => "User-Agent: SilphNet-Landing-Page\r\nAccept: application/vnd.github+json\r\n",
        'timeout' => 5,
        'ignore_errors' => true,
    ]]);
    $body = @file_get_contents($url, false, $ctx);
    if ($body === false) return null;
    $data = json_decode($body, true);
    if (!is_array($data) || isset($data['message'])) return null; // {"message":"Not Found"} etc.
    return $data;
}

$ghRepo = silphnet_github_get('https://api.github.com/repos/AshJamB/SilphNet');
$ghRelease = silphnet_github_get('https://api.github.com/repos/AshJamB/SilphNet/releases/latest');
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SilphNet - Multiplayer Presence Mod for Gen 1 Recomp</title>
<meta name="description" content="A multiplayer presence mod for Pokemon Gen 1 Recomp. Log in, add friends by Trainer ID, and see their last-known positions - no server process required.">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://silphnet.jamshark.co.uk/">
<link rel="icon" type="image/x-icon" href="assets/favicon.ico">
<link rel="icon" type="image/png" sizes="16x16" href="assets/favicon-16.png">
<link rel="icon" type="image/png" sizes="32x32" href="assets/favicon-32.png">
<link rel="icon" type="image/png" sizes="48x48" href="assets/favicon-48.png">
<link rel="apple-touch-icon" sizes="180x180" href="assets/favicon-180.png">

<!-- Open Graph - controls how this page previews when shared (Discord,
     Twitter/X, Facebook, iMessage, etc.) and is also read by several AI
     assistants when summarizing a link. -->
<meta property="og:type" content="website">
<meta property="og:title" content="SilphNet - Multiplayer Presence Mod for Gen 1 Recomp">
<meta property="og:description" content="A multiplayer presence mod for Pokemon Gen 1 Recomp. Log in, add friends by Trainer ID, and see their last-known positions - no server process required, works on desktop and mobile.">
<meta property="og:url" content="https://silphnet.jamshark.co.uk/">
<meta property="og:image" content="https://silphnet.jamshark.co.uk/assets/silphnet-banner.png">
<meta property="og:site_name" content="SilphNet">

<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="SilphNet - Multiplayer Presence Mod for Gen 1 Recomp">
<meta name="twitter:description" content="A multiplayer presence mod for Pokemon Gen 1 Recomp. Log in, add friends by Trainer ID, and see their last-known positions.">
<meta name="twitter:image" content="https://silphnet.jamshark.co.uk/assets/silphnet-banner.png">

<!-- JSON-LD structured data (schema.org) - helps both search engines and
     AI assistants understand what this page/project actually is, beyond
     just the visible text - e.g. that it's a piece of free software with
     a real download location and source repo, not just a generic page
     about Pokemon. SoftwareApplication is the closest schema.org type to
     "a game mod"; there's no more specific "mod" type in the vocabulary. -->
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "SilphNet",
  "applicationCategory": "GameApplication",
  "operatingSystem": "Cross-platform (Gen1Recomp: Windows, macOS, Linux, Android)",
  "description": "A multiplayer presence mod for Pokemon Gen 1 Recomp. Log in with a name and password, get a unique Trainer ID, add friends in-game, and see their last-known positions on the map - no live movement, no server process required beyond ordinary PHP and MySQL hosting.",
  "url": "https://silphnet.jamshark.co.uk/",
  "downloadUrl": "https://github.com/AshJamB/SilphNet",
  "codeRepository": "https://github.com/AshJamB/SilphNet",
  "author": {
    "@type": "Person",
    "name": "Ash Brittain",
    "alternateName": "AshJam",
    "url": "https://ash.jamtv.co.uk"
  },
  "offers": {
    "@type": "Offer",
    "price": "0",
    "priceCurrency": "GBP"
  },
  "image": "https://silphnet.jamshark.co.uk/assets/silphnet-banner.png"
}
</script>
<style>
  :root {
    --bg: #0b0e14;
    --panel: #12161f;
    --panel-border: #262c3a;
    --orange: #f6a935;
    --orange-dark: #c97e1c;
    --blue: #4fc3f7;
    --text: #e8ecf4;
    --text-dim: #9aa4b8;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.6;
  }
  .wrap { max-width: 880px; margin: 0 auto; padding: 24px 20px 64px; }
  header { text-align: center; margin-bottom: 32px; }
  header img { max-width: 100%; width: 420px; height: auto; }
  h1 { display: none; } /* real title is the logo image itself */
  .tagline { color: var(--text-dim); font-size: 1.1rem; max-width: 640px; margin: 0 auto; }
  .cta-row { display: flex; flex-wrap: wrap; gap: 12px; justify-content: center; margin: 28px 0; }
  .btn {
    display: inline-block; padding: 12px 22px; border-radius: 8px; text-decoration: none;
    font-weight: 600; font-size: 0.95rem; border: 2px solid transparent;
  }
  .btn-primary { background: var(--orange); color: #1a1200; }
  .btn-primary:hover { background: var(--orange-dark); }
  .btn-secondary { background: transparent; color: var(--text); border-color: var(--panel-border); }
  .btn-secondary:hover { border-color: var(--blue); color: var(--blue); }
  section { margin: 40px 0; }
  h2 {
    font-size: 1.3rem; color: var(--orange); border-bottom: 2px solid var(--panel-border);
    padding-bottom: 8px; margin-bottom: 16px;
  }
  .card {
    background: var(--panel); border: 1px solid var(--panel-border); border-radius: 12px;
    padding: 20px 24px;
  }
  .feature-grid {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px;
  }
  .feature-grid .card { padding: 16px 18px; }
  .feature-grid .card strong { color: var(--blue); display: block; margin-bottom: 4px; }
  .feature-grid .card p { margin: 0; color: var(--text-dim); font-size: 0.92rem; }
  .gh-card { display: flex; flex-wrap: wrap; gap: 20px; align-items: center; justify-content: space-between; }
  .gh-card .gh-meta { color: var(--text-dim); font-size: 0.9rem; }
  .gh-card .gh-meta strong { color: var(--text); }
  .socials { display: flex; flex-wrap: wrap; gap: 12px; }
  .socials a {
    color: var(--text); text-decoration: none; background: var(--panel);
    border: 1px solid var(--panel-border); border-radius: 8px; padding: 10px 16px; font-size: 0.9rem;
  }
  .socials a:hover { border-color: var(--orange); color: var(--orange); }
  ol { color: var(--text-dim); }
  ol li { margin-bottom: 10px; }
  ol li strong { color: var(--text); }
  code {
    background: #1c2230; padding: 2px 6px; border-radius: 4px; font-size: 0.9em;
    color: var(--orange);
  }
  footer {
    text-align: center; color: var(--text-dim); font-size: 0.85rem;
    border-top: 1px solid var(--panel-border); padding-top: 20px; margin-top: 48px;
  }
  footer a { color: var(--blue); text-decoration: none; }
  footer a:hover { text-decoration: underline; }
  @media (max-width: 480px) {
    header img { width: 280px; }
    .tagline { font-size: 1rem; }
  }

  /* Players-online widget + modal */
  .online-pill {
    display: inline-flex; align-items: center; gap: 8px; background: var(--panel);
    border: 1px solid var(--panel-border); border-radius: 999px; padding: 8px 18px;
    font-size: 0.92rem; cursor: pointer; color: var(--text); margin: 0 auto 8px;
  }
  .online-pill:hover { border-color: var(--blue); }
  .online-pill .dot {
    width: 9px; height: 9px; border-radius: 50%; background: #3ddc73;
    box-shadow: 0 0 6px #3ddc73; flex-shrink: 0;
  }
  .online-pill strong { color: var(--text); }
  .online-pill.is-loading .dot { background: var(--text-dim); box-shadow: none; }

  .modal-overlay {
    display: none; position: fixed; inset: 0; background: rgba(6, 8, 12, 0.72);
    align-items: center; justify-content: center; z-index: 50; padding: 20px;
  }
  .modal-overlay.open { display: flex; }
  .modal-box {
    background: var(--panel); border: 1px solid var(--panel-border); border-radius: 14px;
    padding: 24px 26px; max-width: 380px; width: 100%;
  }
  .modal-box h3 { margin: 0 0 4px; font-size: 1.15rem; color: var(--orange); }
  .modal-box .modal-sub { color: var(--text-dim); font-size: 0.85rem; margin: 0 0 20px; }
  .version-row {
    display: flex; align-items: center; justify-content: space-between;
    padding: 12px 14px; border-radius: 10px; background: #1c2230; margin-bottom: 10px;
    width: 100%; border: 1px solid transparent; cursor: pointer; font: inherit; text-align: left;
  }
  .version-row:hover { border-color: var(--blue); }
  .version-row:last-of-type { margin-bottom: 0; }
  .version-row .v-name { display: flex; align-items: center; gap: 10px; font-weight: 600; color: var(--text); }
  .version-row .v-swatch { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }
  .version-row .v-count-wrap { display: flex; align-items: center; gap: 8px; }
  .version-row .v-count { font-size: 1.1rem; font-weight: 700; color: var(--text); }
  .version-row .v-chevron { color: var(--text-dim); font-size: 0.85rem; }
  .v-swatch.red { background: #e05a5a; }
  .v-swatch.blue { background: #4fc3f7; }
  .v-swatch.yellow { background: #f6d648; }
  .v-swatch.gold { background: #c9a13b; }
  .v-swatch.silver { background: #b9c0c6; }
  .player-list { margin-bottom: 4px; }
  .player-row {
    display: flex; align-items: center; justify-content: space-between;
    padding: 9px 12px; border-radius: 8px; background: #1c2230; margin-bottom: 8px; font-size: 0.9rem;
  }
  .player-row:last-child { margin-bottom: 0; }
  .player-row { align-items: flex-start; }
  .player-row .p-left { display: flex; flex-direction: column; gap: 2px; }
  .player-row .p-name { color: var(--text); font-weight: 600; }
  .player-row .p-location { color: var(--text-dim); font-size: 0.76rem; letter-spacing: 0.02em; }
  .player-row .p-id { color: var(--text-dim); font-size: 0.82rem; flex-shrink: 0; padding-top: 1px; }
  .modal-back {
    background: none; border: none; color: var(--blue); font-size: 0.85rem; cursor: pointer;
    padding: 0; margin-bottom: 14px; display: none;
  }
  .modal-back.show { display: inline-block; }
  .modal-empty { color: var(--text-dim); font-size: 0.88rem; padding: 6px 2px; }
  .modal-close {
    margin-top: 20px; width: 100%; padding: 10px; border-radius: 8px; border: 1px solid var(--panel-border);
    background: transparent; color: var(--text); cursor: pointer; font-size: 0.9rem;
  }
  .modal-close:hover { border-color: var(--blue); color: var(--blue); }

  /* Community stats ticker - a single line that fades between a handful of
     server-wide totals on a slow interval, fetched once on load. A JS
     interval swap was picked over a CSS @keyframes marquee because this
     page has no existing continuous-animation convention to match (its
     only motion today is instant hover-state swaps on .btn/.online-pill/
     .version-row) - a slow crossfade of one line at a time reads as an
     extension of that same "quiet, static-feeling page" tone, where a
     scrolling marquee would stand out as a new and busier kind of motion. */
  .stats-ticker {
    display: none; text-align: center; color: var(--text-dim); font-size: 0.9rem;
    background: var(--panel); border: 1px solid var(--panel-border); border-radius: 999px;
    padding: 8px 18px; margin: 0 auto 18px; max-width: 560px; opacity: 1;
    transition: opacity 0.4s ease;
  }
  .stats-ticker.fade { opacity: 0; }
  .stats-ticker strong { color: var(--text); }

  /* Leaderboards section */
  .lb-tabs { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 16px; }
  .lb-tab {
    background: transparent; border: 1px solid var(--panel-border); color: var(--text-dim);
    border-radius: 999px; padding: 8px 16px; font-size: 0.85rem; cursor: pointer; font-weight: 600;
  }
  .lb-tab:hover { border-color: var(--blue); color: var(--blue); }
  .lb-tab.active { background: var(--orange); border-color: var(--orange); color: #1a1200; }
  .lb-table { width: 100%; border-collapse: collapse; font-size: 0.9rem; }
  .lb-table th {
    text-align: left; color: var(--text-dim); font-weight: 600; font-size: 0.78rem;
    text-transform: uppercase; letter-spacing: 0.04em; padding: 8px 10px; border-bottom: 1px solid var(--panel-border);
  }
  .lb-table td { padding: 10px; border-bottom: 1px solid var(--panel-border); vertical-align: middle; }
  .lb-table tr:last-child td { border-bottom: none; }
  .lb-rank { color: var(--text-dim); font-weight: 700; width: 2em; }
  .lb-name-cell { display: flex; flex-direction: column; gap: 4px; }
  .lb-name-row { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
  .lb-name { color: var(--text); font-weight: 600; }
  .lb-id { color: var(--text-dim); font-size: 0.78rem; }
  .lb-total { color: var(--blue); font-weight: 700; text-align: right; }
  /* Small colored pill next to a name, same visual language as the
     .v-swatch dots above - a title is just another small at-a-glance tag,
     so it reuses this page's existing palette (--orange for the rarest
     tiers, --blue for the rest) rather than introducing new colors. */
  .trainer-title {
    display: inline-block; font-size: 0.68rem; font-weight: 700; text-transform: uppercase;
    letter-spacing: 0.03em; padding: 2px 8px; border-radius: 999px; white-space: nowrap;
    background: rgba(79, 195, 247, 0.15); color: var(--blue); border: 1px solid rgba(79, 195, 247, 0.35);
  }
  .trainer-title.tier-legend, .trainer-title.tier-champion {
    background: rgba(246, 169, 53, 0.15); color: var(--orange); border-color: rgba(246, 169, 53, 0.35);
  }
</style>
</head>
<body>
<div class="wrap">

  <header>
    <img src="assets/silphnet-banner.png" alt="SilphNet - Online Mod for Gen 1 Recomp">
    <p class="tagline">
      A multiplayer presence mod for Pokemon Gen 1 Recomp. Log in, add
      friends by Trainer ID, and see their last-known positions - no
      server process required, works the same on desktop and mobile.
    </p>
    <div class="stats-ticker" id="statsTicker">
      <span id="statsTickerText"></span>
    </div>
    <div style="display: flex; justify-content: center; margin-top: 22px;">
      <button type="button" class="online-pill is-loading" id="onlinePill" aria-haspopup="dialog">
        <span class="dot"></span>
        <span id="onlinePillText">Checking players online&hellip;</span>
      </button>
    </div>
    <div class="cta-row">
      <a class="btn btn-primary" href="https://github.com/AshJamB/SilphNet" target="_blank" rel="noopener">Get SilphNet</a>
      <a class="btn btn-secondary" href="account.php">Manage my account</a>
    </div>
  </header>

  <section>
    <h2>What it does</h2>
    <div class="feature-grid">
      <div class="card">
        <strong>Friends by Trainer ID</strong>
        <p>Add friends entirely in-game with a D-pad digit spinner - no typing, no web page needed.</p>
      </div>
      <div class="card">
        <strong>Last-known positions</strong>
        <p>Friends appear as static map markers where they were last seen - no live movement, no persistent server.</p>
      </div>
      <div class="card">
        <strong>Friend stats & activity</strong>
        <p>Badges, Pokedex progress, League wins, money, and time played - self-reported by each friend's own client.</p>
      </div>
      <div class="card">
        <strong>Party viewer</strong>
        <p>See a friend's current party, one Pokemon per screen - species, level, HP, and moves.</p>
      </div>
      <div class="card">
        <strong>Who's nearby</strong>
        <p>See everyone else (friend or not) currently on your map, Pokemon-Go-style.</p>
      </div>
      <div class="card">
        <strong>Works everywhere</strong>
        <p>Plain HTTP, ordinary PHP + MySQL hosting behind it - runs the same on desktop and mobile, negligible data use.</p>
      </div>
    </div>
  </section>

  <section>
    <h2>Leaderboards</h2>
    <div class="card">
      <div class="lb-tabs" id="lbTabs">
        <button type="button" class="lb-tab active" data-tab="league">League Clears</button>
        <button type="button" class="lb-tab" data-tab="badges">Badges</button>
        <button type="button" class="lb-tab" data-tab="pokedex">Pokedex Caught</button>
      </div>
      <p class="modal-empty" id="lbStatus">Loading leaderboard&hellip;</p>
      <table class="lb-table" id="lbTable" style="display: none;">
        <thead>
          <tr><th>#</th><th>Trainer</th><th style="text-align: right;">Total</th></tr>
        </thead>
        <tbody id="lbTableBody"></tbody>
      </table>
    </div>
  </section>

  <section>
    <h2>Get it on GitHub</h2>
    <div class="card gh-card">
      <div>
        <p style="margin: 0 0 8px;">
          <strong style="color: var(--text); font-size: 1.05rem;">AshJamB/SilphNet</strong>
        </p>
        <p class="gh-meta" style="margin: 0;">
          <?php if ($ghRepo): ?>
            <?php if (!empty($ghRepo['description'])): ?>
              <?php echo htmlspecialchars($ghRepo['description']); ?><br>
            <?php endif; ?>
            <?php if (isset($ghRepo['stargazers_count'])): ?>
              <strong><?php echo (int)$ghRepo['stargazers_count']; ?></strong> stars
            <?php endif; ?>
            <?php if ($ghRelease && !empty($ghRelease['tag_name'])): ?>
              &middot; latest release <strong><?php echo htmlspecialchars($ghRelease['tag_name']); ?></strong>
              <?php if (!empty($ghRelease['published_at'])): ?>
                (<?php echo htmlspecialchars(date('j M Y', strtotime($ghRelease['published_at']))); ?>)
              <?php endif; ?>
            <?php endif; ?>
          <?php else: ?>
            The mod's source, install instructions, and full changelog live here.
          <?php endif; ?>
        </p>
      </div>
      <a class="btn btn-primary" href="https://github.com/AshJamB/SilphNet" target="_blank" rel="noopener">View on GitHub</a>
    </div>
  </section>

  <section>
    <h2>Install</h2>
    <div class="card">
      <ol>
        <li><strong>Get the mod</strong> - download <code>dist/silphnet.zip</code> from
          <a href="https://github.com/AshJamB/SilphNet" target="_blank" rel="noopener" style="color: var(--blue);">GitHub</a>,
          or install it directly from the in-game Mod Manager's Update/Other Versions screen.</li>
        <li><strong>Enable it</strong> - turn on SilphNet in the Mod Manager and allow the <code>network</code> permission when asked.</li>
        <li><strong>Log in</strong> - set MY NAME and PASSWORD in the mod's options. The first login with a new name creates
          an account automatically and assigns a unique Trainer ID.</li>
        <li><strong>Add friends</strong> - open the SilphNet row from the Start Menu, then add friends by entering their Trainer ID.</li>
      </ol>
    </div>
  </section>

  <section>
    <h2>Find me</h2>
    <div class="socials">
      <a href="https://ash.jamtv.co.uk" target="_blank" rel="noopener">ash.jamtv.co.uk</a>
      <a href="https://github.com/AshJamB/SilphNet" target="_blank" rel="noopener">GitHub</a>
      <a href="https://instagram.com/ashjamgram" target="_blank" rel="noopener">Instagram @ashjamgram</a>
      <a href="https://tiktok.com/@ashjam" target="_blank" rel="noopener">TikTok @ashjam</a>
    </div>
  </section>

  <footer>
    SilphNet is free to use - running costs come out of my own pocket. If you'd like to help keep it going,
    you can do so at <a href="https://buymeacoffee.com/ashjam" target="_blank" rel="noopener">buymeacoffee.com/ashjam</a>.
    Entirely optional, and much appreciated.
  </footer>

</div>

<div class="modal-overlay" id="onlineModal" role="dialog" aria-modal="true" aria-labelledby="onlineModalTitle">
  <div class="modal-box">
    <button type="button" class="modal-back" id="onlineModalBack">&larr; Back to all versions</button>
    <h3 id="onlineModalTitle">Players online</h3>
    <p class="modal-sub" id="onlineModalSub">Loading&hellip;</p>
    <div id="onlineVersionRows"></div>
    <div id="onlinePlayerRows" style="display: none;"></div>
    <button type="button" class="modal-close" id="onlineModalClose">Close</button>
  </div>
</div>

<script>
// Two public, unauthenticated endpoints:
//   public_online_status.php  - counts only, drives the pill + summary view
//   public_online_players.php - names + Trainer IDs for ONE version, drives
//                                the drilldown view when a version is clicked
// Split deliberately (see public_online_players.php's own comment) rather
// than one endpoint with an "include names" flag, so it's obvious which
// file is safe-by-default and which one intentionally exposes identity.
const ONLINE_STATUS_API = '/api/public_online_status.php';
const ONLINE_PLAYERS_API = '/api/public_online_players.php';
const VERSION_META = {
  RED: { label: 'Red', swatch: 'red' },
  BLUE: { label: 'Blue', swatch: 'blue' },
  YELLOW: { label: 'Yellow', swatch: 'yellow' },
  // Gen 2, currently Beta in the Gen1Recomp launcher - same treatment as
  // the Gen 1 versions above, just with their own swatch colours.
  GOLD: { label: 'Gold', swatch: 'gold' },
  SILVER: { label: 'Silver', swatch: 'silver' },
};
let lastOnlineData = null;   // cached summary, so "back" doesn't need a re-fetch

// Same fallback formatting main.lua's own friendlyMapName() uses for any
// map_id not in its explicit FRIENDLY_MAP_NAMES table (see
// public_online_players.php's comment on why this isn't shared code) -
// "VICTORY_ROAD" -> "VICTORY ROAD". Good enough for the overwhelming
// majority of real Gen 1 map ids without needing that whole table
// duplicated here in JS too.
function friendlyMapName(mapId) {
  if (!mapId) return 'UNKNOWN';
  return mapId.replace(/_/g, ' ');
}

function renderSummaryView(data) {
  document.getElementById('onlineModalBack').classList.remove('show');
  document.getElementById('onlinePlayerRows').style.display = 'none';
  document.getElementById('onlineVersionRows').style.display = '';
  document.getElementById('onlineModalTitle').textContent = 'Players online';

  const noun = data.total === 1 ? 'player' : 'players';
  document.getElementById('onlineModalSub').textContent = `${data.total} ${noun} online right now - click a version to see who.`;

  const rows = document.getElementById('onlineVersionRows');
  rows.innerHTML = '';
  for (const v of data.versions) {
    const meta = VERSION_META[v.game_version] || { label: v.game_version, swatch: '' };
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'version-row';
    row.innerHTML = `
      <span class="v-name"><span class="v-swatch ${meta.swatch}"></span>${meta.label}</span>
      <span class="v-count-wrap"><span class="v-count">${v.count}</span><span class="v-chevron">&rsaquo;</span></span>
    `;
    row.addEventListener('click', () => showPlayerList(v.game_version, meta.label));
    rows.appendChild(row);
  }
}

async function showPlayerList(gameVersion, label) {
  document.getElementById('onlineModalBack').classList.add('show');
  document.getElementById('onlineVersionRows').style.display = 'none';
  const playerRows = document.getElementById('onlinePlayerRows');
  playerRows.style.display = '';
  playerRows.innerHTML = '<p class="modal-empty">Loading&hellip;</p>';
  document.getElementById('onlineModalTitle').textContent = `${label} online`;
  document.getElementById('onlineModalSub').textContent = '';

  try {
    const res = await fetch(`${ONLINE_PLAYERS_API}?game_version=${encodeURIComponent(gameVersion)}`);
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || 'unknown error');

    if (data.players.length === 0) {
      playerRows.innerHTML = '<p class="modal-empty">Nobody online for this version right now.</p>';
      return;
    }
    playerRows.innerHTML = '';
    const list = document.createElement('div');
    list.className = 'player-list';
    for (const p of data.players) {
      const row = document.createElement('div');
      row.className = 'player-row';
      row.innerHTML = `
        <span class="p-left">
          <span class="p-name"></span>
          <span class="p-location"></span>
        </span>
        <span class="p-id"></span>
      `;
      row.querySelector('.p-name').textContent = p.name;
      row.querySelector('.p-location').textContent = friendlyMapName(p.map_id);
      row.querySelector('.p-id').textContent = `ID ${p.trainer_id}`;
      list.appendChild(row);
    }
    playerRows.appendChild(list);
  } catch (e) {
    playerRows.innerHTML = '<p class="modal-empty">Could not load the player list. Try again.</p>';
  }
}

async function fetchOnlineStatus() {
  const pill = document.getElementById('onlinePill');
  const pillText = document.getElementById('onlinePillText');
  try {
    const res = await fetch(ONLINE_STATUS_API);
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || 'unknown error');

    pill.classList.remove('is-loading');
    const noun = data.total === 1 ? 'player' : 'players';
    pillText.innerHTML = `<strong>${data.total}</strong> ${noun} online`;

    lastOnlineData = data;
    // Only re-render the summary view if the modal isn't currently showing
    // a version drilldown - a background 30s refresh shouldn't yank the
    // visitor back out of the list they're looking at.
    if (!document.getElementById('onlineModalBack').classList.contains('show')) {
      renderSummaryView(data);
    }
  } catch (e) {
    pill.classList.remove('is-loading');
    pillText.textContent = 'Player count unavailable';
  }
}

fetchOnlineStatus();
// Refresh periodically while the page is left open, same 30s cadence the
// mod itself polls presence at (PRESENCE_INTERVAL in main.lua) - no point
// refreshing faster than the data underneath actually changes.
setInterval(fetchOnlineStatus, 30000);

const onlineModal = document.getElementById('onlineModal');
document.getElementById('onlinePill').addEventListener('click', () => {
  if (lastOnlineData) renderSummaryView(lastOnlineData);
  onlineModal.classList.add('open');
});
document.getElementById('onlineModalBack').addEventListener('click', () => {
  if (lastOnlineData) renderSummaryView(lastOnlineData);
});
document.getElementById('onlineModalClose').addEventListener('click', () => {
  onlineModal.classList.remove('open');
});
onlineModal.addEventListener('click', (e) => {
  if (e.target === onlineModal) onlineModal.classList.remove('open');
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') onlineModal.classList.remove('open');
});

// Leaderboards section - one fetch of public_leaderboards.php on page load,
// cached client-side as three pre-ranked lists; tab clicks only toggle
// which cached list is rendered, they never refetch - same "fetch once,
// render many times from memory" shape as this page's own lastOnlineData
// cache above, just with three lists instead of one.
const LEADERBOARDS_API = '/api/public_leaderboards.php';
let lbData = null;
let lbActiveTab = 'league';

// Maps a title string to a CSS modifier class, so the rarer/harder titles
// (SilphNet Legend, Champion) get the --orange treatment already used
// elsewhere on this page for "the notable/primary thing", while the more
// common titles stay --blue - same two-color hierarchy the page already
// uses for primary vs secondary buttons.
function titleTierClass(title) {
  if (title === 'SilphNet Legend' || title === 'Champion') return 'tier-legend';
  return '';
}

function renderLeaderboardTab() {
  const status = document.getElementById('lbStatus');
  const table = document.getElementById('lbTable');
  const body = document.getElementById('lbTableBody');
  if (!lbData) return;

  const list = lbData[lbActiveTab] || [];
  if (list.length === 0) {
    table.style.display = 'none';
    status.style.display = '';
    status.textContent = 'No entries yet for this leaderboard.';
    return;
  }

  status.style.display = 'none';
  table.style.display = '';
  body.innerHTML = '';
  list.forEach((p, i) => {
    const tr = document.createElement('tr');
    const tierClass = titleTierClass(p.title);
    tr.innerHTML = `
      <td class="lb-rank">${i + 1}</td>
      <td>
        <div class="lb-name-cell">
          <div class="lb-name-row">
            <span class="lb-name"></span>
            <span class="trainer-title ${tierClass}"></span>
          </div>
          <span class="lb-id"></span>
        </div>
      </td>
      <td class="lb-total"></td>
    `;
    tr.querySelector('.lb-name').textContent = p.name;
    tr.querySelector('.trainer-title').textContent = p.title;
    tr.querySelector('.lb-id').textContent = `ID ${p.trainer_id}`;
    tr.querySelector('.lb-total').textContent = p.total;
    body.appendChild(tr);
  });
}

async function fetchLeaderboards() {
  const status = document.getElementById('lbStatus');
  try {
    const res = await fetch(LEADERBOARDS_API);
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || 'unknown error');
    lbData = data;
    renderLeaderboardTab();
  } catch (e) {
    // Degrade gracefully, same as the GitHub release card and online
    // widget above - never a raw error, never a broken/empty-looking table.
    status.style.display = '';
    status.textContent = 'Leaderboards are unavailable right now.';
  }
}

document.getElementById('lbTabs').addEventListener('click', (e) => {
  const btn = e.target.closest('.lb-tab');
  if (!btn) return;
  lbActiveTab = btn.dataset.tab;
  for (const t of document.querySelectorAll('.lb-tab')) t.classList.toggle('active', t === btn);
  renderLeaderboardTab();
});

fetchLeaderboards();

// Community stats ticker - fetched once on load, then cycles through a
// handful of pre-built phrases with a simple opacity crossfade (see the
// .stats-ticker CSS comment for why this was chosen over a @keyframes
// marquee). Stays hidden entirely on fetch failure rather than showing an
// empty/broken bar - this page uses no emoji anywhere else (see the
// tagline, feature cards, footer above), so these phrases match that
// plain-text tone rather than introducing emoji here.
const COMMUNITY_STATS_API = '/api/public_community_stats.php';
const TICKER_INTERVAL_MS = 5000;

function buildTickerPhrases(data) {
  return [
    `<strong>${data.online_now}</strong> trainer${data.online_now === 1 ? '' : 's'} online right now`,
    `<strong>${data.total_trainers}</strong> registered trainers`,
    `<strong>${data.total_pokedex_caught}</strong> Pokemon caught by the SilphNet community`,
    `<strong>${data.total_league_clears}</strong> league clears and counting`,
    `<strong>${data.total_badges}</strong> badges earned across all trainers`,
  ];
}

async function fetchCommunityStats() {
  const ticker = document.getElementById('statsTicker');
  const tickerText = document.getElementById('statsTickerText');
  try {
    const res = await fetch(COMMUNITY_STATS_API);
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || 'unknown error');

    const phrases = buildTickerPhrases(data);
    let i = 0;
    tickerText.innerHTML = phrases[0];
    ticker.style.display = '';

    setInterval(() => {
      ticker.classList.add('fade');
      setTimeout(() => {
        i = (i + 1) % phrases.length;
        tickerText.innerHTML = phrases[i];
        ticker.classList.remove('fade');
      }, 400); // matches the 0.4s opacity transition in CSS
    }, TICKER_INTERVAL_MS);
  } catch (e) {
    // Fails soft - the ticker just never appears, no broken/empty bar,
    // same degrade-gracefully rule as the GitHub release card.
    ticker.style.display = 'none';
  }
}

fetchCommunityStats();
</script>
</body>
</html>
