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
    display: inline-flex; align-items: center; gap: 8px; padding: 12px 22px; border-radius: 8px;
    text-decoration: none; font-weight: 600; font-size: 0.95rem; border: 2px solid transparent;
    cursor: pointer; font-family: inherit;
  }
  .btn-icon { width: 16px; height: 16px; flex-shrink: 0; }
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

  /* Secondary stat-counter row (Pokemon Seen/Caught, Badges, League
     Victories) - sits directly under the online-pill, same pill shape and
     palette but smaller/quieter so four of them read as secondary to the
     one main "players online" pill above. Each opens the same kind of
     version-drilldown modal the online pill does, just for a static
     aggregate total instead of a live player list. */
  .stat-row { display: flex; flex-wrap: wrap; gap: 10px; justify-content: center; margin: 0 auto 8px; }
  .stat-pill {
    display: inline-flex; align-items: center; gap: 7px; background: var(--panel);
    border: 1px solid var(--panel-border); border-radius: 999px; padding: 6px 14px;
    font-size: 0.82rem; cursor: pointer; color: var(--text-dim);
  }
  .stat-pill:hover { border-color: var(--blue); color: var(--text); }
  .stat-pill .stat-icon { width: 15px; height: 15px; flex-shrink: 0; color: var(--orange); }
  .stat-pill strong { color: var(--text); }
  .stat-pill.is-loading { opacity: 0.6; cursor: default; }
  @media (max-width: 480px) {
    .stat-pill { font-size: 0.78rem; padding: 6px 11px; }
  }

  .modal-overlay {
    display: none; position: fixed; inset: 0; background: rgba(6, 8, 12, 0.72);
    align-items: center; justify-content: center; z-index: 50; padding: 20px;
  }
  .modal-overlay.open { display: flex; }
  .modal-box {
    background: var(--panel); border: 1px solid var(--panel-border); border-radius: 14px;
    padding: 24px 26px; max-width: 380px; width: 100%;
    /* The stat modal can now hold a 5-row version breakdown plus a
       10-row "Top Contributors" table underneath it - taller than any
       modal content before this addition, so this needs to be able to
       scroll on a short viewport instead of overflowing off-screen. */
    max-height: 85vh; overflow-y: auto;
  }
  .modal-box h3 { margin: 0 0 4px; font-size: 1.15rem; color: var(--orange); }
  .modal-box .modal-sub { color: var(--text-dim); font-size: 0.85rem; margin: 0 0 20px; }
  /* Smaller, secondary heading for a second block of content inside a
     modal that already has its own h3 title (e.g. "Top Contributors"
     under the stat modal's per-version breakdown) - same orange accent
     as modal-box h3 but visually subordinate to it. A plain top margin
     alone read as "squished" against the version rows above it once
     both were actually on the page together (reported directly) - a
     real border-top divider plus more breathing room above it makes the
     two blocks read as clearly separate sections instead of one run-on
     list, the same way the leaderboard "card" elsewhere on this page is
     visually separated from the section above it. */
  .stat-modal-subheading {
    margin: 28px 0 12px; padding-top: 20px; font-size: 0.95rem; color: var(--orange);
    border-top: 1px solid var(--panel-border);
  }
  .version-row {
    display: flex; align-items: center; justify-content: space-between;
    padding: 12px 14px; border-radius: 10px; background: #1c2230; margin-bottom: 10px;
    width: 100%; border: 1px solid transparent; cursor: pointer; font: inherit; text-align: left;
  }
  .version-row:hover { border-color: var(--blue); }
  .version-row:last-of-type { margin-bottom: 0; }
  /* Used for the stat-by-version modal's rows, which are plain <div>s (no
     further drilldown, unlike the online modal's clickable version rows
     above) - same look, just without the pointer cursor/hover affordance
     that would wrongly suggest these are clickable too. */
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
  .v-swatch.crystal { background: #4dd0c4; }
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
  .bug-field {
    width: 100%; padding: 9px 11px; margin-bottom: 12px; border-radius: 8px;
    border: 1px solid var(--panel-border); background: #1c2230; color: var(--text);
    font-size: 0.92rem; font-family: inherit; box-sizing: border-box; resize: vertical;
  }
  .bug-field:focus { outline: none; border-color: var(--blue); }

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
    <div class="stat-row" id="statRow">
      <button type="button" class="stat-pill is-loading" id="statPillSeen" aria-haspopup="dialog" data-stat="pokedex_seen">
        <svg class="stat-icon" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <ellipse cx="8" cy="8" rx="6.5" ry="4" stroke="currentColor" stroke-width="1.3"/>
          <circle cx="8" cy="8" r="1.7" fill="currentColor"/>
        </svg>
        <span class="stat-pill-text">&hellip;</span>
      </button>
      <button type="button" class="stat-pill is-loading" id="statPillCaught" aria-haspopup="dialog" data-stat="pokedex_caught">
        <svg class="stat-icon" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <circle cx="8" cy="8" r="6.5" stroke="currentColor" stroke-width="1.3"/>
          <line x1="1.5" y1="8" x2="14.5" y2="8" stroke="currentColor" stroke-width="1.3"/>
          <circle cx="8" cy="8" r="1.7" fill="currentColor"/>
        </svg>
        <span class="stat-pill-text">&hellip;</span>
      </button>
      <button type="button" class="stat-pill is-loading" id="statPillBadges" aria-haspopup="dialog" data-stat="badges">
        <svg class="stat-icon" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <path d="M8 1.2 14 4v4.2C14 12 11.4 14.2 8 15c-3.4-.8-6-3-6-6.8V4Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/>
        </svg>
        <span class="stat-pill-text">&hellip;</span>
      </button>
      <button type="button" class="stat-pill is-loading" id="statPillLeague" aria-haspopup="dialog" data-stat="league_wins">
        <svg class="stat-icon" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <path d="M4 2.5h8v3.2c0 2.4-1.8 4.3-4 4.3s-4-1.9-4-4.3V2.5Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/>
          <path d="M4 3.2H2.2c0 1.9.7 3.1 2.1 3.5M12 3.2h1.8c0 1.9-.7 3.1-2.1 3.5" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/>
          <line x1="8" y1="10" x2="8" y2="12.3" stroke="currentColor" stroke-width="1.3"/>
          <path d="M5.3 14.5c0-1 1.2-1.7 2.7-1.7s2.7.7 2.7 1.7Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/>
        </svg>
        <span class="stat-pill-text">&hellip;</span>
      </button>
      <button type="button" class="stat-pill is-loading" id="statPillTiles" aria-haspopup="dialog" data-stat="tiles_walked">
        <svg class="stat-icon" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <ellipse cx="5.2" cy="4.5" rx="2" ry="3" transform="rotate(-15 5.2 4.5)" stroke="currentColor" stroke-width="1.3"/>
          <ellipse cx="10.8" cy="11.5" rx="2" ry="3" transform="rotate(15 10.8 11.5)" stroke="currentColor" stroke-width="1.3"/>
        </svg>
        <span class="stat-pill-text">&hellip;</span>
      </button>
    </div>
    <div class="cta-row">
      <a class="btn btn-primary" href="https://github.com/AshJamB/SilphNet" target="_blank" rel="noopener">Get SilphNet</a>
      <a class="btn btn-secondary" href="account.php">Manage My Account</a>
    </div>
    <div class="cta-row">
      <button type="button" class="btn btn-secondary" id="reportBugOpen">
        <svg class="btn-icon" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <rect x="5.5" y="5" width="5" height="7" rx="2.5" stroke="currentColor" stroke-width="1.2"/>
          <line x1="8" y1="2" x2="8" y2="5" stroke="currentColor" stroke-width="1.2"/>
          <line x1="5.5" y1="6.5" x2="2.5" y2="4.5" stroke="currentColor" stroke-width="1.1"/>
          <line x1="10.5" y1="6.5" x2="13.5" y2="4.5" stroke="currentColor" stroke-width="1.1"/>
          <line x1="5" y1="8.5" x2="2" y2="8.5" stroke="currentColor" stroke-width="1.1"/>
          <line x1="11" y1="8.5" x2="14" y2="8.5" stroke="currentColor" stroke-width="1.1"/>
          <line x1="5.5" y1="10.5" x2="2.5" y2="12.5" stroke="currentColor" stroke-width="1.1"/>
          <line x1="10.5" y1="10.5" x2="13.5" y2="12.5" stroke="currentColor" stroke-width="1.1"/>
        </svg>
        Report a bug
      </button>
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
        <button type="button" class="lb-tab" data-tab="seen">Pokedex Seen</button>
        <button type="button" class="lb-tab" data-tab="tiles">Tiles Walked</button>
        <button type="button" class="lb-tab" data-tab="dex_pct">Dex Completion</button>
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

<!-- Report-a-bug modal - shares the same .modal-overlay/.modal-box/
     .modal-close CSS every other modal on this page uses. website is a
     honeypot field: real visitors never see it (position:absolute,
     off-screen, aria-hidden, tabindex=-1 below), but a simple bot that
     fills in every field in a form finds it anyway - report_bug.php
     silently discards anything submitted with it non-empty. -->
<div class="modal-overlay" id="bugReportModal" role="dialog" aria-modal="true" aria-labelledby="bugReportTitle">
  <div class="modal-box">
    <h3 id="bugReportTitle">Report a bug</h3>
    <p class="modal-sub">This becomes an issue on the SilphNet GitHub repo.</p>
    <form id="bugReportForm">
      <label for="bugTitle" style="display: block; font-size: 0.82rem; color: var(--text-dim); margin-bottom: 4px;">What went wrong</label>
      <input type="text" id="bugTitle" name="title" maxlength="100" class="bug-field" placeholder="e.g. Friend marker doesn't disappear" required>
      <label for="bugDescription" style="display: block; font-size: 0.82rem; color: var(--text-dim); margin-bottom: 4px;">Details - what happened, what you expected instead</label>
      <textarea id="bugDescription" name="description" maxlength="2000" rows="4" class="bug-field" required></textarea>
      <input type="text" id="bugWebsite" name="website" tabindex="-1" autocomplete="off" aria-hidden="true" style="position: absolute; left: -9999px; width: 1px; height: 1px; opacity: 0;">
      <p class="modal-empty" id="bugReportStatus" style="display: none;"></p>
      <button type="submit" class="modal-close" id="bugReportSubmit" style="margin-top: 6px; border-color: var(--blue); color: var(--blue);">Submit report</button>
    </form>
    <button type="button" class="modal-close" id="bugReportClose">Close</button>
  </div>
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

<!-- Community stat modal - shares the same .modal-overlay/.modal-box/
     .version-row/.v-swatch CSS the online-pill modal above uses, but is
     its own separate modal instance (own ids, own JS handlers) rather
     than a generalized/shared modal component - keeps the existing
     online-drilldown code completely untouched.
     Two views, same "back button swaps visibility" pattern the online
     modal already established: the top view (version breakdown + a
     combined-total Top Contributors list) is view 1; clicking a version
     row drills into view 2, that ONE version's own per-player ranking
     (public_stat_by_version.php - see its own comment on why this is a
     genuinely different ranking than the combined Top Contributors list
     above it, not just the same data re-filtered client-side). -->
<div class="modal-overlay" id="statModal" role="dialog" aria-modal="true" aria-labelledby="statModalTitle">
  <div class="modal-box">
    <button type="button" class="modal-back" id="statModalBack">&larr; Back to all versions</button>
    <h3 id="statModalTitle">Stat by version</h3>
    <p class="modal-sub" id="statModalSub">Loading&hellip;</p>
    <div id="statVersionRows"></div>
    <div id="statTopContributorsWrap">
      <h3 class="stat-modal-subheading">Top Contributors</h3>
      <div id="statTopContributors"></div>
    </div>
    <div id="statPlayerRows" style="display: none;"></div>
    <button type="button" class="modal-close" id="statModalClose">Close</button>
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
  // Gen 2 - Gold and Silver are no longer Beta in the Gen1Recomp launcher
  // (confirmed against the engine's own src/core/GameVersion.lua: their
  // launcherName is now just "Gold"/"Silver", no "(Beta)" suffix). Crystal
  // is the new one still marked Beta there ("Crystal (Beta)") - shares
  // Gold/Silver's same save format one-for-one (main.lua's isGen2()), just
  // its own swatch colour here.
  GOLD: { label: 'Gold', swatch: 'gold' },
  SILVER: { label: 'Silver', swatch: 'silver' },
  CRYSTAL: { label: 'Crystal', swatch: 'crystal' },
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
    // dex_pct is the one tab whose "total" is a 0-100 percentage rather
    // than a plain count (see public_leaderboards.php's own comment on
    // that list) - shown with a trailing "%" here only, every other tab
    // renders its number as-is same as before.
    tr.querySelector('.lb-total').textContent = lbActiveTab === 'dex_pct' ? `${p.total}%` : p.total;
    body.appendChild(tr);
  });
}

// A single in-flight promise, not just the eventual lbData cache - the
// stat-modal "top contributors" list (see showStatModal below) can be
// opened before this page-load fetch has actually resolved yet, and
// needs to AWAIT the same request rather than firing a second one or
// reading lbData while it's still null.
let lbFetchPromise = null;

function fetchLeaderboards() {
  const status = document.getElementById('lbStatus');
  lbFetchPromise = (async () => {
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
  })();
  return lbFetchPromise;
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
    `<strong>${data.total_tiles_walked}</strong> tiles walked in-game`,
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

    // Stat-counter row (Pokemon Seen/Caught, Badges, League Victories) -
    // rendered from this SAME already-fetched response, no second network
    // round trip. Unlike the online-pill's player-list drilldown (which
    // genuinely needs a fresh fetch since presence is live/changing),
    // these are static aggregate totals that don't change mid-visit, so
    // caching the one fetch this page already makes for the ticker is
    // enough to drive both the pill numbers AND the per-version modal.
    communityStatsData = data;
    renderStatPills(data);
  } catch (e) {
    // Fails soft - the ticker just never appears, no broken/empty bar,
    // same degrade-gracefully rule as the GitHub release card.
    ticker.style.display = 'none';
    for (const cfg of Object.values(STAT_META)) {
      const pill = document.getElementById(cfg.pillId);
      pill.classList.remove('is-loading');
      pill.querySelector('.stat-pill-text').textContent = 'Stats unavailable';
    }
  }
}

// Static per-stat metadata for the secondary counter row under the
// online-pill - each maps a friend_stats column (as returned by
// public_community_stats.php's "versions" array) to its pill's DOM id and
// modal copy. Kept as one small table rather than four near-duplicate
// blocks of pill/modal-wiring code below.
// lbKey ties each stat back to the matching list in public_leaderboards.php
// (lbData.seen/pokedex/badges/league - see fetchLeaderboards above) so the
// "top contributors" mini-list inside each stat's modal can reuse that
// SAME already-fetched, already-tiebroken (see that endpoint's own
// alphabetical-tiebreak comment) ranking rather than a second endpoint or
// a second sort implemented here in JS.
const STAT_META = {
  pokedex_seen: { pillId: 'statPillSeen', label: 'Pokemon Seen', modalTitle: 'Pokemon Seen by Version', lbKey: 'seen' },
  pokedex_caught: { pillId: 'statPillCaught', label: 'Pokemon Caught', modalTitle: 'Pokemon Caught by Version', lbKey: 'pokedex' },
  badges: { pillId: 'statPillBadges', label: 'Gym Badges Earned', modalTitle: 'Gym Badges Earned by Version', lbKey: 'badges' },
  league_wins: { pillId: 'statPillLeague', label: 'League Victories', modalTitle: 'League Victories by Version', lbKey: 'league' },
  tiles_walked: { pillId: 'statPillTiles', label: 'Tiles Walked', modalTitle: 'Tiles Walked by Version', lbKey: 'tiles' },
};
const STAT_MODAL_TOP_N = 10;
let communityStatsData = null; // cached community-stats response, reused by every stat pill's modal

function renderStatPills(data) {
  for (const [key, cfg] of Object.entries(STAT_META)) {
    const pill = document.getElementById(cfg.pillId);
    pill.classList.remove('is-loading');
    const total = data.versions.reduce((sum, v) => sum + (v[key] || 0), 0);
    pill.querySelector('.stat-pill-text').innerHTML = `<strong>${total.toLocaleString()}</strong> ${cfg.label}`;
  }
}

// Shared by both the "Top Contributors" combined list and the per-version
// player drilldown below - both are the exact same {name, trainer_id,
// total} shape, just sourced from different endpoints/scopes, so one
// renderer keeps their markup/behaviour identical instead of two
// near-duplicate table-building blocks.
function renderRankedTable(container, list, emptyText) {
  container.innerHTML = '';
  if (list.length === 0) {
    container.innerHTML = `<p class="modal-empty">${emptyText}</p>`;
    return;
  }
  const table = document.createElement('table');
  table.className = 'lb-table';
  table.innerHTML = '<thead><tr><th>#</th><th>Trainer</th><th style="text-align: right;">Total</th></tr></thead><tbody></tbody>';
  const body = table.querySelector('tbody');
  list.forEach((p, i) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="lb-rank">${i + 1}</td>
      <td><span class="lb-name"></span> <span class="lb-id"></span></td>
      <td class="lb-total"></td>
    `;
    tr.querySelector('.lb-name').textContent = p.name;
    tr.querySelector('.lb-id').textContent = `ID ${p.trainer_id}`;
    tr.querySelector('.lb-total').textContent = p.total;
    body.appendChild(tr);
  });
  container.appendChild(table);
}

// Renders the per-version breakdown, highest count first (owner's own
// request - "order them by most to least") rather than the fixed
// RED/BLUE/YELLOW/GOLD/SILVER/CRYSTAL tracked-version order the API
// returns them in. Sorted here in JS on a COPY of the array (slice) - communityStatsData
// is shared/cached across every stat's modal, so mutating its own
// versions array in place would leave the NEXT stat modal opened
// re-sorted by the wrong stat's numbers.
//
// Each row is now clickable (owner's own request - "clicking into the
// versions tells you specifically the stats for that person within that
// version, similar to clicking into a version when clicking whose
// online") - drills into showStatVersionPlayers below, the exact same
// summary-row-click-opens-detail shape the online-pill modal already
// uses for its own version rows.
function renderStatVersionRows(statKey) {
  const rows = document.getElementById('statVersionRows');
  rows.innerHTML = '';
  const sorted = [...communityStatsData.versions].sort((a, b) => (b[statKey] || 0) - (a[statKey] || 0));
  for (const v of sorted) {
    const meta = VERSION_META[v.game_version] || { label: v.game_version, swatch: '' };
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'version-row';
    row.innerHTML = `
      <span class="v-name"><span class="v-swatch ${meta.swatch}"></span>${meta.label}</span>
      <span class="v-count-wrap"><span class="v-count">${(v[statKey] || 0).toLocaleString()}</span><span class="v-chevron">&rsaquo;</span></span>
    `;
    row.addEventListener('click', () => showStatVersionPlayers(statKey, v.game_version, meta.label));
    rows.appendChild(row);
  }
}

// Top-contributors mini-list inside the modal - the owner's own request
// ("have a leaderboard in here of people who have contributed the most").
// Reuses the SAME public_leaderboards.php list the Leaderboards section's
// own tabs already show (via STAT_META's lbKey - see its own comment) -
// same names, same totals, same alphabetical tiebreak for genuine ties
// (e.g. two accounts both sitting at 8/8 Kanto badges) - rather than a
// second ranking implemented differently here. This is the COMBINED
// (across every version) ranking - see showStatVersionPlayers for the
// separate per-version-only ranking one click deeper.
function renderStatTopContributors(statKey) {
  const cfg = STAT_META[statKey];
  const list = ((lbData && lbData[cfg.lbKey]) || []).slice(0, STAT_MODAL_TOP_N);
  renderRankedTable(document.getElementById('statTopContributors'), list, 'No contributors yet.');
}

// Second-level drilldown - one specific version's own per-player ranking
// for this stat (public_stat_by_version.php), fetched fresh on click same
// as the online modal's showPlayerList does for who's-online-in-this-
// version. Deliberately a live fetch, not a client-side re-filter of
// already-fetched data - unlike the aggregate totals this page already
// caches, this is a genuinely different ranking (per-version, not
// combined-across-versions) that this page has no other copy of yet.
async function showStatVersionPlayers(statKey, gameVersion, versionLabel) {
  document.getElementById('statModalBack').classList.add('show');
  document.getElementById('statVersionRows').style.display = 'none';
  document.getElementById('statTopContributorsWrap').style.display = 'none';
  const playerRows = document.getElementById('statPlayerRows');
  playerRows.style.display = '';
  playerRows.innerHTML = '<p class="modal-empty">Loading&hellip;</p>';
  document.getElementById('statModalTitle').textContent = `${STAT_META[statKey].label} - ${versionLabel}`;
  document.getElementById('statModalSub').textContent = '';

  try {
    const res = await fetch(`${STAT_BY_VERSION_API}?stat=${encodeURIComponent(statKey)}&game_version=${encodeURIComponent(gameVersion)}`);
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || 'unknown error');
    renderRankedTable(playerRows, data.players, `Nobody has any yet on ${versionLabel}.`);
  } catch (e) {
    playerRows.innerHTML = '<p class="modal-empty">Could not load this version’s breakdown. Try again.</p>';
  }
}

function showStatModalSummary(statKey) {
  const cfg = STAT_META[statKey];
  document.getElementById('statModalBack').classList.remove('show');
  document.getElementById('statPlayerRows').style.display = 'none';
  document.getElementById('statVersionRows').style.display = '';
  document.getElementById('statTopContributorsWrap').style.display = '';
  document.getElementById('statModalTitle').textContent = cfg.modalTitle;
  document.getElementById('statModalSub').textContent = communityStatsData
    ? 'Totals by game version, highest first.' : 'Stats unavailable right now.';
}

let statModalCurrentKey = null;   // so the back button knows which stat to return to

async function showStatModal(statKey) {
  statModalCurrentKey = statKey;
  showStatModalSummary(statKey);

  const rows = document.getElementById('statVersionRows');
  rows.innerHTML = '';
  document.getElementById('statTopContributors').innerHTML = '<p class="modal-empty">Loading&hellip;</p>';
  statModal.classList.add('open');

  if (communityStatsData) renderStatVersionRows(statKey);

  // lbData may not have resolved yet if this modal is opened very soon
  // after page load - await the SAME in-flight request fetchLeaderboards
  // already started, rather than firing a second one.
  if (!lbData && lbFetchPromise) await lbFetchPromise;
  renderStatTopContributors(statKey);
}

const STAT_BY_VERSION_API = '/api/public_stat_by_version.php';
const statModal = document.getElementById('statModal');
document.getElementById('statRow').addEventListener('click', (e) => {
  const btn = e.target.closest('.stat-pill');
  if (!btn) return;
  showStatModal(btn.dataset.stat);
});
document.getElementById('statModalBack').addEventListener('click', () => {
  showStatModalSummary(statModalCurrentKey);
});
document.getElementById('statModalClose').addEventListener('click', () => {
  statModal.classList.remove('open');
});
statModal.addEventListener('click', (e) => {
  if (e.target === statModal) statModal.classList.remove('open');
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') statModal.classList.remove('open');
});

// Report-a-bug modal - a plain POST to report_bug.php (see that file for
// the honeypot/rate-limit design). Disables the submit button while the
// request is in flight so a slow connection can't be double-submitted by
// an impatient click, and shows an inline status line for both the error
// and success case rather than an alert() - consistent with how every
// other failure on this page degrades (a text message in place, not a
// popup).
const BUG_REPORT_API = '/api/report_bug.php';
const bugReportModal = document.getElementById('bugReportModal');
const bugReportForm = document.getElementById('bugReportForm');
const bugReportStatus = document.getElementById('bugReportStatus');
const bugReportSubmit = document.getElementById('bugReportSubmit');

function openBugReportModal() {
  bugReportStatus.style.display = 'none';
  bugReportModal.classList.add('open');
}
document.getElementById('reportBugOpen').addEventListener('click', openBugReportModal);
document.getElementById('bugReportClose').addEventListener('click', () => {
  bugReportModal.classList.remove('open');
});
bugReportModal.addEventListener('click', (e) => {
  if (e.target === bugReportModal) bugReportModal.classList.remove('open');
});

bugReportForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const title = document.getElementById('bugTitle').value.trim();
  const description = document.getElementById('bugDescription').value.trim();
  bugReportStatus.style.display = '';
  bugReportStatus.style.color = '';
  if (!title || !description) {
    bugReportStatus.textContent = 'Please fill in both what went wrong and the details.';
    return;
  }

  bugReportSubmit.disabled = true;
  bugReportSubmit.textContent = 'Submitting…';
  bugReportStatus.textContent = '';
  try {
    const res = await fetch(BUG_REPORT_API, { method: 'POST', body: new FormData(bugReportForm) });
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || 'unknown error');
    bugReportStatus.textContent = 'Thanks - your report was filed. Closing…';
    setTimeout(() => {
      bugReportModal.classList.remove('open');
      bugReportForm.reset();
      bugReportStatus.style.display = 'none';
    }, 1500);
  } catch (err) {
    bugReportStatus.textContent = err.message || 'Could not submit that. Please try again in a minute.';
  } finally {
    bugReportSubmit.disabled = false;
    bugReportSubmit.textContent = 'Submit report';
  }
});

fetchCommunityStats();
</script>
</body>
</html>
