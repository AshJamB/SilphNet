# SilphNet

A multiplayer layer for [Pokémon Gen 1 Recomp](https://github.com/bryanthaboi/gen1recomp) —
built so it works **on Android**, not just desktop.

**Status: Milestone 1 (shared overworld) + Phase 1 (accounts) — built and
tested.** Trainers connected to the same server see each other walk the same
map in real time, behind a login that follows them across devices and
reinstalls. Chat, avatars, trading and battles are later milestones.

## Why this works on Android (when Gen1Online doesn't)

Gen1Recomp runs on LÖVE 11, whose Android build has **no TLS/SSL**. The
existing Gen1Online mod talks to its server over `https://`, so on Android the
request dies before it leaves the app — that's the "CANNOT CONNECT" you hit.

SilphNet instead uses a **plain-TCP** protocol. Raw sockets are bundled on
every LÖVE platform and are *not* subject to Android's cleartext-traffic rule
(that only applies to Java's HTTP stack). No certificates, no luasec — it just
works, on phone and PC alike. The trade-off is that traffic isn't encrypted,
which is fine for a fan overworld that only exchanges positions and a chosen
trainer name.

## Layout

```
mod/silphnet/         the LÖVE mod (install this into the game's mods/ folder)
  main.lua            client: TCP thread, login (challenge-response), remote trainers
  manifest.json       declares the "network" permission
  mod.card            manager detail card
dist/silphnet.zip     the mod, zipped and ready to install
server/
  silphnet_server.py  the relay + account server (Python 3, standard library only)
  sim_client.py       a dev tool that fakes a trainer, to test the server
  silphnet.service    systemd unit for running it on a VPS
  DEPLOY.md           how to host it on a cheap Linux VPS (+ scaling notes)
ACCOUNTS.md           the account model (in-game now, website login later)
SECURITY.md           what the no-TLS trade-off means and how logins stay safe
```

## Quick start

### 1. Run the server (a PC on your Wi-Fi, or a VPS)

```
cd server
python3 silphnet_server.py          # listens on 0.0.0.0:7788
```

On a PC, find its LAN address so your phone can reach it:

- Windows: `ipconfig` → the **IPv4 Address** under your Wi-Fi adapter, e.g.
  `192.168.1.50`. If Windows Firewall prompts, allow Python on **Private
  networks** (or open inbound TCP 7788).

To host it so it's reachable from anywhere and stays up, put it on a cheap Linux
VPS instead — see [server/DEPLOY.md](server/DEPLOY.md). Then use the VPS's public
IP as the server host.

### 2. Install the mod

- **Desktop:** copy `mod/silphnet/` into the game's `mods/` folder, or install
  `dist/silphnet.zip` from the in-game Mod Manager.
- **Android:** get `dist/silphnet.zip` onto the phone (cloud drive, USB,
  whatever's easy) and install it from the in-game Mod Manager. Because this
  repo is private, the manager's "install from GitHub" won't reach it — use the
  zip.

Enable **SilphNet** in the Mod Manager. It will ask to allow the `network`
permission.

### 3. Point the mod at your server

In the Mod Manager → **SilphNet** options:

- **SERVER HOST** = your PC's IPv4 (e.g. `192.168.1.50`), **SERVER PORT** =
  `7788`.
- If entering dots is fiddly on the phone, turn on **HOST AS NUMBERS** and fill
  the four **HOST NUM** boxes (`192`, `168`, `1`, `50`).

Also set **MY NAME** and a **PASSPHRASE** — that's your account. The first time
you connect with a name it's created; after that the passphrase proves it and a
device token is cached so you don't retype it. On another device, enter the same
name + passphrase to log into the same account. The passphrase is verified by a
SHA-256 challenge and **never sent in the clear** (see `SECURITY.md`). One
caveat for now: the passphrase is stored in the mod's options on the device —
fine for personal use; Phase 2 moves logins to a website so it isn't.

### 4. Play

Load a save and walk around Pallet Town. Anyone else connected to the same
server on the same map appears and moves in real time. Open **START** — the menu
shows `SILPHNET <n>` (trainers nearby), `SILPHNET ...` while connecting/logging
in, or `SILPHNET OFF` if it hasn't reached the server.

**Seeing movement needs two clients.** With a single device you'll connect, log
in, and see `SILPHNET 0` (nobody else there yet) — which already confirms the
server, login and networking all work. To watch trainers move, add a second
client: a mate's phone, another device, or the game on PC once you install it.

You can prove the server works with no game at all:

```
cd server
python3 silphnet_server.py &
python3 sim_client.py --auth register --name ALICE --password test --map PALLET_TOWN
python3 sim_client.py --auth register --name BOB   --password test --map PALLET_TOWN  # another terminal
```

Each simulated trainer logs in and then prints the other as it moves.

## Troubleshooting

- **`SILPHNET OFF`** → the client couldn't reach the server. Check the
  host/port, that the server is running, that you're on the same network (or the
  VPS IP is right), and that the firewall allows the port. The server prints a
  line whenever a client connects and logs in — watch its console (or
  `journalctl -u silphnet -f` on a VPS) to see whether your phone gets through.
- **`SILPHNET SET NAME/PASS`** → set MY NAME and a PASSPHRASE in the mod
  options; that pair is your account.
- **`SILPHNET LOGIN FAIL`** → wrong passphrase for an existing name, or the name
  is already taken by someone else. Change it in the options and it retries.
- **Mod errors** → the Mod Manager lists them per-mod, prefixed `[silphnet]`.
  Those messages are the fastest way to iterate.

## What's verified vs. what to check on-device

Verified here (server tests + a stubbed-engine run of the client's logic):

- The relay + accounts: register, duplicate-name, right/wrong passphrase
  (challenge-response), token re-login, bad token, per-map position relay, and
  disconnect cleanup.
- The client: the login flow (`HI`/`LOGIN`/`AUTH`/`TOK`/`REG`) computing SHA-256
  proofs that match the server exactly, plus the spawn / walk / despawn /
  map-change logic.

Marked `<< VERIFY >>` in `main.lua` (engine specifics I couldn't run without
the game) — the likely first tweaks after your first on-device run:

- the remote-trainer `sprite` id (`SPRITE_RED`) and the exact `spawnNpc`
  object fields;
- that `render.letterbox` is an acceptable per-frame tick in your build.

If something misbehaves, the `[silphnet]` manager errors will point right at it.

## Roadmap

1. ✅ Shared overworld
2. ✅ Accounts — name + passphrase, SHA-256 challenge-response, device tokens (Phase 1)
3. In-game chat overlay
4. Avatar selection
5. Face-to-face trade / battle requests (relayed through the engine's `LinkBattle`)
6. Website accounts on Supabase + pairing login (Phase 2); always-on internet server

See `ACCOUNTS.md` for the account design and `SECURITY.md` for the security model.

## Notes

Private repo, pushed manually via GitHub Desktop. The `SilphNet_Technical_
Specification` files are the original Gemini design study — see the project
notes for the review of what holds up and what doesn't.
