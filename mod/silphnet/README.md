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

Then load a save and walk around. Open **START** to see `SILPHNET <name>`
once logged in, or a status message otherwise. Select that row for the
status screen: **A** retries login, **START** opens the friends list,
**SELECT** resets the cached login on this device, **B** goes back.

## Notes

- Needs the `network` permission (declared) because it makes HTTP requests.
- No HTTPS/TLS is used on purpose — see `../../SECURITY.md` for what that
  means and how passwords stay safe anyway (hashed server-side, never
  stored in plaintext).
- No live/real-time movement by design — see the main README's "Why this
  isn't real-time" section. The original real-time relay is retired in
  `../../archive/tcp_relay_retired/`.
- Friend requests currently go through `add_friend.php`/`accept_friend.php`
  directly (no in-game screen for it yet) — see `../../README.md` roadmap.
