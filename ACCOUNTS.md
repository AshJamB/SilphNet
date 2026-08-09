# SilphNet accounts — approach

**Goals:** one account that works on mobile *and* PC, survives reinstalls and
new phones, and can grow into a proper website login later.

## The one constraint that shapes everything

The **game client** (LÖVE 11) can't do TLS on Android. Everything *else* can —
your browser, and the VPS. So the rule is simple:

> The game must never carry a raw password. Anything sensitive happens over
> HTTPS (browser or server side); the game only ever holds a **token**.

That single rule turns the "no encryption" problem from a worry into a
non-issue, and your website idea is exactly what makes it possible.

## Recommended: two phases

### Phase 1 — in-game accounts ✅ implemented (no website needed)

- **Identity:** a trainer name + a passphrase the player chooses.
- **Login:** challenge-response. Server sends a one-time `nonce`; the client
  replies `SHA-256(nonce + SHA-256(passphrase))` using `love.data.hash`. The
  passphrase itself never crosses the wire.
- **Server stores** only a salted hash of the passphrase — never the passphrase.
- **On success** the server issues a **device token** cached in `mod.save`, so
  the same device auto-logs-in next launch.
- **Cross-device today:** type your name + passphrase on any device — phone or
  PC — and you're in the same account. New phone or reinstall? Just log in
  again. This solves the "can I get back in?" worry immediately, no website
  required.

### Phase 2 — website accounts (when you get the site)

- **Sign-up / login on the website over HTTPS.** Let a real auth backend do the
  things a Game Boy text box shouldn't: proper password hashing, email verify,
  password reset. **Supabase (Auth + Postgres)** is the clean fit here, and a
  small **Vercel** site is the natural front for it.
- **Linking the game:** the player logs in on the web and gets a short
  **pairing code** (like a console "enter this code" screen); they type it once
  in-game, and the game swaps it for a device token. The password never touches
  the game.
- **The VPS relay validates tokens against Supabase over HTTPS** — the VPS can
  do TLS; only the game client can't. So the sensitive leg is always encrypted.

## Where each piece runs

| Piece | Runs on | Talks over |
|---|---|---|
| Realtime relay (positions, later battles/trades) | **your VPS** | plain TCP (game) |
| Accounts, passwords, email/reset | **Supabase** (Phase 2) | HTTPS |
| Optional web front-end / pairing page | **Vercel** (Phase 2) | HTTPS |
| Game client | phone / PC | holds a **token** only |

The VPS is doing the one job serverless can't (a persistent socket loop); the
web/account stuff lives on the platforms built for it. No conflict — they each
do what they're good at.

## Migration: Phase 1 → Phase 2 is smooth

If we build Phase 1 with identity = an `accountId` (+ display name) and hand out
**device tokens** from day one, then moving to Phase 2 only swaps *where the
credential is checked* (in-game passphrase → web-issued pairing token). The game
protocol and the device tokens don't change, and Phase 1 accounts can be carried
over.

## Security recap

- No raw password ever crosses the plain-TCP channel in **either** phase.
- Tokens are opaque, per-device, and revocable. A sniffed token lets someone
  impersonate one game session until it's revoked — annoying, not catastrophic,
  and no credential leaks.
- Full transport encryption comes back automatically if Gen1Recomp ever moves
  to LÖVE 12 (native HTTPS on Android).

## My recommendation

Build **Phase 1 now** — it already gives you cross-device, reinstall-proof
accounts with no website and no cleartext passwords — and architect it so
Phase 2 (website + Supabase) drops in later when you're ready to buy the domain.
