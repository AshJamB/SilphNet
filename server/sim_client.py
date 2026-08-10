#!/usr/bin/env python3
"""
SilphNet simulated client - dev/test tool (NOT part of the game).

Mirrors exactly what the Lua mod does on the wire, so it verifies the server's
accounts + challenge-response auth and the movement relay without the game.

Auth then (optionally) walk east a few tiles, printing peers seen.

Examples:
    python3 sim_client.py --auth register --name ALICE --password hunter2 --map PALLET_TOWN
    python3 sim_client.py --auth login    --name ALICE --password hunter2 --map PALLET_TOWN
    python3 sim_client.py --auth token    --name ALICE --token <hex>
Prints RESULT=... and (on success) TOKEN=... for scripted chaining.
"""

import argparse
import hashlib
import secrets
import select
import socket
import time


def sha(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=7788)
    ap.add_argument("--auth", choices=["register", "login", "token"], required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--password", default="")
    ap.add_argument("--token", default="")
    ap.add_argument("--sprite", default="SPRITE_RED")
    ap.add_argument("--map", default="")
    ap.add_argument("--x", type=int, default=5)
    ap.add_argument("--y", type=int, default=6)
    ap.add_argument("--steps", type=int, default=6)
    ap.add_argument("--seconds", type=float, default=6.0)
    args = ap.parse_args()

    sock = socket.create_connection((args.host, args.port))
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    rfile = sock.makefile("r", encoding="utf-8", newline="\n")

    def send(line):
        sock.sendall((line + "\n").encode("utf-8"))

    send("HI|2")

    ok, token = False, ""
    if args.auth == "register":
        salt = secrets.token_hex(8)
        send(f"REG|{args.name}|{args.sprite}|{salt}|{sha(salt + args.password)}")
        rep = rfile.readline().strip()
    elif args.auth == "login":
        send(f"LOGIN|{args.name}")
        first = rfile.readline().strip()              # CHAL|salt|nonce  or  ERR|...
        if first.startswith("CHAL|"):
            _, salt, nonce = first.split("|")
            proof = sha(sha(salt + args.password) + nonce)
            send(f"AUTH|{proof}")
            rep = rfile.readline().strip()
        else:
            rep = first                               # e.g. ERR|NO_ACCOUNT
    else:  # token
        send(f"TOK|{args.name}|{args.token}")
        rep = rfile.readline().strip()

    print(f"[{args.name}] RESULT={rep}")
    if rep.startswith("OK|"):
        ok = True
        token = rep.split("|")[3]
        print(f"[{args.name}] TOKEN={token}")

    if not ok or not args.map:
        send("B"); sock.close(); return

    # movement phase
    x = args.x
    send(f"P|{args.map}|{x}|{args.y}|down")
    deadline = time.time() + args.seconds
    step, seen, next_move = 0, set(), time.time() + 0.4
    # NOTE: deliberately not using sock.settimeout() here. Python's
    # socket.makefile() "poisons" itself the first time a read times out -
    # every read after that raises a plain OSError instead of
    # socket.timeout/TimeoutError, so a try/except around readline() stops
    # catching anything and the script crashes. select.select() lets us wait
    # up to `remaining` seconds for data WITHOUT ever touching the socket's
    # own timeout, so readline() is only called once we already know data
    # (or EOF) is waiting.
    while time.time() < deadline:
        remaining = max(0.0, min(0.3, deadline - time.time()))
        ready, _, _ = select.select([sock], [], [], remaining)
        if ready:
            line = rfile.readline().strip()
            if line.startswith("S|"):
                _, _m, rest = line.split("|", 2)
                for chunk in filter(None, rest.split(";")):
                    pid, name, sprite, px, py, facing = chunk.split(",")
                    tag = f"{name}@({px},{py})"
                    if tag not in seen:
                        seen.add(tag)
                        print(f"[{args.name}] sees peer: {tag}")
        if step < args.steps and time.time() >= next_move:
            x += 1; step += 1
            send(f"P|{args.map}|{x}|{args.y}|right")
            next_move = time.time() + 0.4
    send("B"); sock.close()
    print(f"[{args.name}] done. distinct peer sightings: {len(seen)}")


if __name__ == "__main__":
    main()
