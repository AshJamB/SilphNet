# Retired: real-time TCP relay (SILPHNET LIVE)

This folder holds the original real-time multiplayer relay - a background
TCP server (`silphnet_server.py`), its test client (`sim_client.py`), and
VPS deployment notes (`DEPLOY.md`, `silphnet.service`).

**Why retired:** this needed a persistent process running somewhere at all
times (either a home PC left on 24/7, or a paid VPS) to relay live
positions between players. That didn't fit "just PHP+MySQL on my existing
cPanel hosting," and it also fought a persistent movement judder that
traced back to the game engine's own `handle:scriptMove` having a real
per-call cost - never fully resolved cleanly even after several rounds of
fixes (cooldown pacing, then bypassing scriptMove entirely with direct
engine-internals writes, then a hand-rolled walk tween).

SilphNet v1.0.0 replaced this entirely with an async, PHP+MySQL-backed
presence system (see `server/web/`) - no persistent process required,
works entirely on cPanel hosting, and has none of the live-relay's
architectural problems. Friends show up as static "last known position"
markers instead of live-moving avatars.

Kept here (rather than deleted) in case any of the account-auth logic,
protocol design notes, or VPS deployment steps are ever useful again -
full git history is also available if you want to see exactly how this
evolved.
