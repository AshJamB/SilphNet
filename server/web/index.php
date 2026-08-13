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
</body>
</html>
