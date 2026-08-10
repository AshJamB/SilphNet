# SilphNet (mod)

See other trainers walking around the same map in real time, behind an
account that follows you across devices/reinstalls. Uses a plain-TCP
connection instead of HTTPS, which is why it works **on Android** too
(LÖVE 11 has no TLS there).

## Try it

1. Start a SilphNet server somewhere reachable (see `../../server/`):
   `python3 silphnet_server.py`
2. Install this `silphnet` folder (or `dist/silphnet.zip`) as a mod and
   enable it in the Mod Manager.
3. Open **SilphNet** options. Press **A** on a field to open the Game Boy
   letter-grid entry screen. This mod adds a **0–9** row to that grid for
   its own four fields only (everywhere else in the game stays vanilla):
   - **SERVER HOST** / **SERVER PORT** — where the server is (`.` lives in
     the symbols row just above "ED").
   - **MY NAME** / **PASSPHRASE** — your account. First login on a name
     creates it; later logins prove it with a hashed challenge (the
     passphrase is never sent in the clear) and a device token is cached so
     you don't retype it every launch.

Then load a save and walk around. Anyone else connected to the same server on
the same map appears and moves in real time. Open **START** to see
`SILPHNET <n>` (trainers nearby), `SILPHNET SET NAME/PASS` /
`SILPHNET LOGIN FAIL` if login needs attention, or `SILPHNET OFF` if it hasn't
connected.

## Notes

- Needs the `network` permission (declared) because it opens a socket.
- No HTTPS/TLS is used on purpose — see `../../SECURITY.md` for what that
  trades away and how logins stay safe anyway.
- Movement + accounts only for now. Chat, avatars, trades and battles are
  later milestones — see `../../README.md`.
