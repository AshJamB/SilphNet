# SilphNet: Technical Architecture & Feature Specification
**Project Name:** SilphNet (Gen1Recomp MMO & Co-op Framework)  
**Target Engine:** Gen1Recomp (LÖVE2D / Lua Engine for Android & PC)  
**Author / Lead Engineer:** Independent Developer  
**Status:** Architecture Design & Implementation Blueprint  

---

## Executive Summary & Core Vision

**SilphNet** is an open-source, auto-connecting multiplayer framework built for **Gen1Recomp**. While existing community mods (such as *Gen1Online*) rely on fragmented peer-to-peer hosting, manual IP entry, and complex in-game PC terminal menus, **SilphNet** delivers a seamless, zero-configuration "log in and play" overworld MMO experience.

By combining a lightweight **Lua client mod** running in a non-blocking background thread with a high-performance **Go / Node.js spatial server** hosted on a single $5/month Linux VPS, SilphNet renders other trainers across Kanto in real-time. It integrates a native Friends List overlay, anti-cheat validated PvP battling, and cloud trading—all without requiring end users to manage ports or network settings.

---

## System Architecture Overview

SilphNet uses a client-server architecture where the client acts as a thin renderer/input collector, while the server maintains world state, spatial partitioning, and security validation.

```
+-------------------------------------------------------------------------+
|                        Gen1Recomp Client (Lua)                          |
|                                                                         |
|  +---------------------------+       +-------------------------------+  |
|  |   Main Engine (60 FPS)    |       |   love.thread Network Loop    |  |
|  | - LÖVE2D Overworld Render |<----->| - Async Non-blocking Socket   |  |
|  | - UI Overlay / Menus      |       | - WSS / HTTPS Handlers        |  |
|  +---------------------------+       +---------------+---------------+  |
+------------------------------------------------------+------------------+
                                                       | WSS / HTTPS
                                                       v
+-------------------------------------------------------------------------+
|                         Linux VPS Infrastructure                        |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  |                 Caddy Reverse Proxy (Auto TLS / SSL)              |  |
|  +---------------------------------+---------------------------------+  |
|                                    | Loopback (127.0.0.1)               |
|                                    v                                    |
|  +---------------------------------+---------------------------------+  |
|  |               SilphNet Server (Go / Node.js)                      |  |
|  | - Auth & Token Manager (JWT)                                      |  |
|  | - Spatial Broadcast Engine (10 Hz Tick / Map Grouping)              |  |
|  | - Anti-Cheat Stat Recalculator & Movepool Referee                 |  |
|  +---------------------------------+---------------------------------+  |
|                                    | Local Loopback                     |
|                                    v                                    |
|  +-------------------------------------------------------------------+  |
|  |                    SQLite / PostgreSQL Database                   |  |
|  +-------------------------------------------------------------------+  |
+-------------------------------------------------------------------------+
```

### Key Architectural Principles
1. **Zero-Config Auto-Connect:** The client hardcodes or fetches the backend endpoint (`wss://silphnet.yourdomain.com`), completely removing manual IP entry and port forwarding for players.
2. **Non-Blocking Threading:** Network sockets run inside a dedicated `love.thread` in Lua. Network latency, packet drops, or slow buffers will never freeze or stutter the main 60 FPS rendering loop.
3. **Single-Box Local Loopback:** The reverse proxy, game backend, and database run on a single Linux VPS. Local IPC/loopback (`127.0.0.1`) ensures sub-millisecond database queries without multi-node network overhead.

---

## Network Protocol & Spatial State Engine

### Spatial Partitioning by `map_id`
Kanto features over 100 distinct map environments (e.g., `Pallet_Town`, `Route_1`, `Celadon_Gym`). SilphNet utilizes spatial partitioning based on `map_id`:
* Connected clients are grouped strictly into room pools corresponding to their active `map_id`.
* Movement updates are broadcast **only** to clients sharing the same map.
* This eliminates $O(N^2)$ global broadcasting bottlenecks and reduces room scaling to isolated $O(M^2)$ pools, allowing thousands of total players to populate the world simultaneously.

### Binary Packet Payload Layout
To minimize bandwidth and CPU overhead, positional state is transmitted as a raw binary buffer (~10 bytes) at a **10 Hz tick rate** (10 updates/second):

| Field Offset | Field Name | Data Type | Description |
| :--- | :--- | :--- | :--- |
| `0x00 - 0x01` | `player_id` | `uint16` (2B) | Unique session ID assigned upon login |
| `0x02 - 0x03` | `map_id` | `uint16` (2B) | Active map location ID |
| `0x04` | `x_tile` | `uint8` (1B) | X-coordinate on tile grid (0–255) |
| `0x05` | `y_tile` | `uint8` (1B) | Y-coordinate on tile grid (0–255) |
| `0x06` | `facing_dir` | `uint8` (1B) | Facing direction (`0=Down`, `1=Up`, `2=Left`, `3=Right`) |
| `0x07` | `sprite_id` | `uint8` (1B) | Selected overworld trainer avatar |
| `0x08` | `anim_state` | `uint8` (1B) | Movement animation frame index |

* **Client Linear Interpolation (Lerping):** The client smoothly interpolates entity positions between 100ms ticks to render fluid 60 FPS movement.

---

## Client UI & Social Experience

* **Authentication & Profiles:** JWT-based persistent logins stored locally on the client device.
* **Start Menu Social Overlay:** Custom Lua canvas drawing hooks into Gen1Recomp's pause menu to render:
  * **Friends List:** Shows online status, active route/town location, and lead party Pokémon.
  * **Direct Overworld Interaction:** Facing an online player and pressing **A** opens a contextual modal: **Battle Challenge**, **Trade Request**, or **Profile View**.
* **Lore Integration:** Named **SilphNet** after Silph Co., the primary tech corporation spanning both Kanto and Johto (powers Magnet Train, Pokégear, and teleporters).

---

## Anti-Cheat & Competitive Integrity Engine

Since local save files on Android/PC can be edited with memory tools, the server acts as an authoritative referee before allowing competitive PvP battles or trades.

### Server-Side Stat Formula Verification
When a player initiates a competitive battle, their party metadata (Species ID, Level, DVs, Stat EXP) is uploaded to the backend. The server recalculates stats using official Gen 1 formulas:

$$\text{HP} = \left\lfloor \frac{(\text{Base} + \text{DV}) \times 2 + \left\lfloor \frac{\sqrt{\text{StatEXP}}}{4} \right\rfloor \times \text{Level}}{100} \right\rfloor + \text{Level} + 10$$

$$\text{Stat} = \left\lfloor \frac{(\text{Base} + \text{DV}) \times 2 + \left\lfloor \frac{\sqrt{\text{StatEXP}}}{4} \right\rfloor \times \text{Level}}{100} \right\rfloor + 5$$

* **Strict Bounds Enforcement:** DVs bounded to $[0, 15]$; Stat EXP bounded to $[0, 65535]$. Any mismatch results in instant disconnection.
* **Movepool Whitelisting:** Movesets are validated against a canonical Gen 1 JSON lookup table.

---

## Infrastructure & Deployment Specification

* **Recommended VPS Spec:** 1–2 vCPUs, 1–2 GB RAM, 25 GB NVMe SSD, 1–2 TB Monthly Bandwidth (~$5/month on Hetzner or DigitalOcean).
* **Estimated Capacity:** 1,000 to 5,000+ concurrent players on a single $5 VPS node.
* **Technology Stack:**
  * **Proxy:** Caddy (Automated HTTPS/WSS SSL via Let's Encrypt).
  * **Backend:** Go (compiled binary) running as a `systemd` background service.
  * **Database:** SQLite (file-based, zero network overhead, sub-millisecond local queries).

---

## Legal & Monetization Framework

* **Non-Profit Fan Project:** 100% free and open-source. No paid items, microtransactions, cosmetics, or subscription paywalls.
* **Transparent Hardware Expense Funding:** Server costs covered via a public tip jar (Ko-fi or Open Collective) capped at the monthly VPS bill ($5/month). Zero in-game perks given for donations to avoid Nintendo copyright/commercialization enforcement.

---

## Concrete Prompts for Claude Code Scaffold

Feed the following prompts sequentially to **Claude Code** to generate the project repository:

### Prompt 1: Backend Server (Go + WebSockets + SQLite)
> "Create a high-performance, single-binary Go backend using Gorilla WebSockets and SQLite. Implement JWT token authentication (`/api/register`, `/api/login`), a Friends table, and a 10 Hz spatial WebSocket handler (`/ws`). Group connected clients by `map_id` and broadcast binary positional packets (`player_id`, `map_id`, `x`, `y`, `facing_dir`, `sprite_id`) only to clients in the same map."

### Prompt 2: Anti-Cheat & Stat Calculator Module
> "Write a standalone Go package that validates Gen 1 Pokémon party data. Implement exact Gen 1 HP and Stat calculation formulas using Base Stats, DVs (0-15), Stat EXP (0-65535), and Level. Compare calculated stats against incoming client stats and include a movepool validator function using a embedded JSON map of legal Gen 1 move IDs per Pokémon."

### Prompt 3: Lua Client Mod for Gen1Recomp
> "Write a LÖVE2D Lua client mod module for Gen1Recomp. Initialize a non-blocking WebSocket connection inside a secondary `love.thread`. Send a 10-byte positional packet whenever the player moves tiles, parse incoming neighbor positional updates, and provide a global table `SilphNet.NearbyPlayers` so the main render loop can draw remote player sprites smoothly."

### Prompt 4: Caddy & Systemd Deployment Scripts
> "Create a Dockerfile, Caddyfile (handling reverse proxying for `wss://silphnet.yourdomain.com` with auto-SSL), and a Systemd service file (`silphnet.service`) to deploy this Go binary and SQLite database on an Ubuntu 24.04 Linux VPS."
