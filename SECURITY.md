# SilphNet security notes

Short version: **the plain-TCP connection is not encrypted, so do not send
reusable passwords over it in cleartext.** That's not a weird hole we
accidentally opened — it's just the ordinary state of a plaintext network
protocol (like old HTTP or IRC). Below is what that means and how to stay safe
anyway.

## What dropping HTTPS actually cost us

TLS/HTTPS normally gives three things. Using plain TCP, we gave up all three:

- **Confidentiality** — with TLS, nobody on the network path can read the
  bytes. Without it, anyone who can see the traffic (someone on the same
  Wi-Fi, a malicious router/hotspot, in principle the ISP) can read everything,
  **including a password sent in the clear.**
- **Server authentication** — TLS certificates prove you're talking to the real
  server. Without them, an attacker could impersonate the server
  (man-in-the-middle), capture credentials, or tamper with messages.
- **Integrity** — TLS detects tampering. Plain TCP doesn't.

So: **a password sent over this as-is could be sniffed.** The worst real-world
harm isn't the game account — it's *password reuse*. If a player types a
password they also use elsewhere, capturing it here compromises those other
accounts too.

## Why we can't just "turn TLS back on" (yet)

The whole reason SilphNet exists is that **LÖVE 11 has no TLS on Android** —
that's what blocks Gen1Online there. Client-side TLS in Lua needs a library
(luasec/lua-https) that isn't available on the Android LÖVE 11 build. The clean
fix is **LÖVE 12**, which ships native HTTPS (lua-https) on every platform
including Android; if/when Gen1Recomp moves to LÖVE 12 we can add an encrypted
transport. That's not in our hands today.

## The good news: we can protect passwords without TLS

LÖVE 11 *does* include `love.data.hash` (SHA-256 and friends). That lets us do
a **challenge-response** so the password never crosses the wire:

1. Server sends a random one-time `nonce`.
2. Client sends `SHA-256(nonce + SHA-256(password))` — never the password
   itself.
3. Server checks it against the stored password hash.

Passive sniffing then can't recover the password, and the nonce stops simple
replay. (An *active* man-in-the-middle could still hijack the session afterward,
because the rest of the traffic is still cleartext — but that's a much higher
bar than "someone sniffed a password on the café Wi-Fi.")

## Recommended approach for a fan game

Match the effort to the stakes. This exchanges positions and a chosen trainer
name — no payments, no real personal data.

- **LAN / just mates:** cleartext is fine. Don't worry about it.
- **Public server, simplest safe option (recommended):** no passwords at all.
  Use a **random per-account token** (like Gen1Online does): the server issues
  it on first login, the client stores it, and auth = presenting the token. A
  sniffed token only lets someone impersonate *that game account* — annoying,
  not catastrophic, and there's no password to reuse-leak.
- **If you want human passwords:** use the **challenge-response** above so the
  password is never sent in the clear, and tell players plainly: *"hobby server
  — don't reuse an important password."* That honesty is itself a real control.

## Server-side hardening (independent of the above)

- The server currently has **no auth at all** — any client can claim any
  trainer id. Add token auth before opening signups.
- It already sanitizes input and rate-limits per connection; keep validating
  everything server-side and never trust client-reported stats (that's the
  anti-cheat work for a later milestone).
- Run it unprivileged behind a firewall (see [server/DEPLOY.md](server/DEPLOY.md)).

## Roadmap

1. ✅ **Challenge-response passphrase + device tokens** — implemented (Phase 1).
   The passphrase never crosses the wire; the server stores only a salted hash;
   a nonce stops replay. Caveat: on the device the passphrase currently sits in
   the mod's options (`options.lua`) — fine for personal use; Phase 2 removes it.
2. **Website accounts** (Supabase + pairing token) — moves passwords off the
   device entirely, behind the browser's HTTPS (Phase 2).
3. **Encrypted transport** in-game if/when Gen1Recomp moves to LÖVE 12
   (native HTTPS on Android).
