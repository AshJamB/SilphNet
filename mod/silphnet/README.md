# SilphNet (mod)

See other trainers walking around the same map in real time. This is
**Milestone 1** — a "walking skeleton" that proves live multiplayer works in
Gen1Recomp, **including on Android**, by using a plain-TCP connection instead
of HTTPS.

## Try it

1. Start a SilphNet server somewhere reachable (see `../../server/`):
   `python3 silphnet_server.py`
2. Install this `silphnet` folder as a mod and enable it in the Mod Manager.
3. In the Mod Manager, open **SilphNet** options and set **SERVER HOST** (and
   **SERVER PORT**, default 7788) to the machine running the server. If typing
   an IP with dots is awkward, turn on **HOST AS NUMBERS** and use the four
   **HOST NUM** boxes instead.

Then load a save and walk around. Anyone else connected to the same server and
standing on the same map appears as a trainer and moves in real time. Open the
**START** menu to see `SILPHNET <n>` (how many trainers are nearby) or
`SILPHNET OFF` if it hasn't connected.

## Notes

- Needs the `network` permission (declared) because it opens a socket.
- No HTTPS/TLS is used on purpose — that is what makes it work on Android,
  where LÖVE 11 has no SSL.
- Movement only for now. Battles, trades and chat are later milestones.
