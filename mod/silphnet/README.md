# SilphNet (mod)

See where your friends were last, without any server of your own running.
Log in with a name and password, and this mod periodically reports your
position to a small PHP+MySQL API and shows friends' last-known positions
back — as static markers on the map and in a friends list. No real-time
movement, no persistent server process. Uses plain `http://` instead of
HTTPS, which is why it works **on Android** too (LÖVE 11 has no TLS there).

## Try it

1. Set up the web API once — see `../../server/web/` and the main
   `../../README.md` "Quick start" section (run `schema.sql`, upload the
   PHP files, set `API_BASE` at the top of `main.lua` to match).
2. Install this `silphnet` folder (or `dist/silphnet.zip`) as a mod and
   enable it in the Mod Manager.
3. Open **SilphNet** options. Press **A** on a field to open the Game Boy
   letter-grid entry screen. This mod adds a **0–9** row to that grid for
   its own two fields only (everywhere else in the game stays vanilla):
   - **MY NAME** / **PASSWORD** — your account. First login on a name
     creates it automatically; later logins use the same name + password
     from any device. A session token is cached so you don't retype it
     every launch.

Then load a save and walk around. Open **START** to see `SN <name>`
once logged in, or a status message otherwise (kept short — "SN", not
"SILPHNET" — since some third-party UI mods truncate long Start Menu
rows rather than adding an ellipsis). Select that row for the status
screen: **A** opens the friends list once logged in (or retries login
before that), **START** re-authenticates, **SELECT** resets the cached
login on this device, **B** goes back. Two more top-level rows sit below
it — **SN NEARBY** (everyone else on your current map) and **SN ONLINE**
(everyone online across the whole service, by game version) — plus **SN
RECOVER ACCT**, which only appears when this account has no recovery
email on file and disappears on its own once one's set (kept top-level
rather than tucked into a submenu, since it's rare but time-critical). A
final **SN MORE** row opens a small submenu for the rows that are
always visible once logged in: **MILESTONES**, **REPORT BUG** (points
to the "Report a bug" button on the website's homepage — no in-game
text entry, see below), and **ABOUT**.

## Notes

- Needs the `network` permission (declared) because it makes HTTP requests.
- No HTTPS/TLS is used on purpose — see `../../SECURITY.md` for what that
  means and how passwords stay safe anyway (hashed server-side, never
  stored in plaintext).
- No live/real-time movement by design — see the main README's "Why this
  isn't real-time" section. The original real-time relay is retired in
  `../../archive/tcp_relay_retired/`.
- Friend requests have their own in-game screens — **RIGHT** from the
  status screen opens Add Friend (digit-spinner Trainer ID entry, no
  typing), **LEFT** opens pending requests to accept. `add_friend.php`/
  `accept_friend.php` are just the server side of that flow, not a
  workaround for a missing in-game screen.
- Supports Gen 1 (Red/Blue/Yellow) and Gen 2 (Gold/Silver/Crystal).
- Every gym (Gen1 Kanto, Gen2 Johto, Gen2 Kanto) has its own sign
  listing which of your accepted friends already hold that gym's badge,
  placed at runtime near wherever you walk in (never a hardcoded
  coordinate — this project ships no ROM data). A second sign near the
  Elite Four entrance (`INDIGO_PLATEAU_LOBBY`) is "SN RECORDS" — it
  cycles (via **A**) through three ranked categories on one sign: total
  league clears, Pokedex completion (best single save), and tiles
  walked. Each category has its own ALL PLAYERS/FRIENDS page and an
  ascending/descending toggle. Both signs only ever show server-computed
  names/numbers — no free text.
- Friend activity reports catching a Pokemon (real-time, event-driven),
  plus earning a badge, leveling up, and winning the League (all three
  detected by diffing successive stats snapshots, since neither a
  badge-earned event nor a stable/documented level-up event exists in
  the engine's mod API).
- SN MILESTONES tracks five small, personal (not server-ranked) social
  firsts — see the Start Menu walkthrough above.
- SN REPORT BUG (inside SN MORE) points to the "Report a bug" button on
  the website's homepage rather than adding an in-game text box — the
  form files a real issue on the GitHub repo directly, asks for no name
  or email, and is guarded by a honeypot field plus a per-IP rate limit
  rather than requiring a SilphNet login.
