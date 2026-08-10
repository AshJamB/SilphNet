#!/usr/bin/env python3
"""
SilphNet relay server - Milestone 1 + Phase 1 accounts.

A tiny, dependency-free TCP relay for Pokemon Gen 1 Recomp's SilphNet mod:
trainers see each other move around the same map in real time, and log in to
an account that follows them across devices and reinstalls.

WHY PLAIN TCP (NO HTTPS)
    Gen1Recomp runs on LOVE 11, whose Android build has no TLS. Raw sockets
    work everywhere and aren't subject to Android's cleartext rule (that only
    applies to Java's HTTP stack). So the wire is a plain, newline-delimited
    text protocol - and the passphrase is NEVER sent in the clear (see AUTH).

WIRE PROTOCOL (one message per line, '\\n' terminated, UTF-8; '|'-separated)

  Handshake / auth (client -> server):
    HI|<proto>                               open (proto = 2)
    REG|<name>|<sprite>|<salt>|<pwHash>      create account
                                             pwHash = sha256(salt + passphrase)
    LOGIN|<name>                             begin passphrase login
    AUTH|<proof>                             answer challenge
                                             proof = sha256(pwHash + nonce)
    TOK|<name>|<token>                       device-token login (no passphrase)

  Auth replies (server -> client):
    CHAL|<salt>|<nonce>                      challenge for LOGIN
    OK|<accountId>|<name>|<token>            authenticated; store the token
    ERR|<code>|<message>                     NAME_TAKEN, NO_ACCOUNT, BAD_AUTH,
                                             BAD_TOKEN, NEED_FIELDS, PROTO

  Session (only after OK):
    client -> server:  P|<map>|<x>|<y>|<facing>      B
    server -> client:  S|<map>|<p1>;<p2>;...         (peers on your map)
                       where each <p> = accountId,name,sprite,x,y,facing

SECURITY (see ../SECURITY.md)
    The passphrase never crosses the wire; the server stores only a salted
    hash; the nonce stops replay. Tokens are bearer secrets over cleartext -
    a sniffed token impersonates one game account until revoked, but leaks no
    passphrase. A determined sniffer can still offline-brute-force a WEAK
    passphrase from (salt, nonce, proof) - so encourage decent passphrases;
    Phase 2 (website + TLS) closes that gap.

RUN
    python3 silphnet_server.py                 # 0.0.0.0:7788
    python3 silphnet_server.py --port 7788
"""

import argparse
import hashlib
import json
import os
import re
import secrets
import socket
import threading
import time

PROTOCOL_VERSION = 2
TICK_SECONDS = 0.12
STALE_AFTER_SECONDS = 20.0
ACCOUNTS_PATH = os.environ.get(
    "SILPHNET_ACCOUNTS",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "accounts.json"))

_SANITIZE = re.compile(r"[|;,\r\n]")


def clean(s, fallback=""):
    s = _SANITIZE.sub("", str(s or "")).strip()
    return s or fallback


def sha256_hex(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# Accounts (persisted)
# ---------------------------------------------------------------------------

_accounts = {}                 # name_lower -> account dict
_accounts_lock = threading.RLock()


def load_accounts():
    global _accounts
    if os.path.exists(ACCOUNTS_PATH):
        try:
            with open(ACCOUNTS_PATH, "r", encoding="utf-8") as f:
                _accounts = json.load(f)
        except Exception as e:
            print(f"[accounts] load error: {e}")
            _accounts = {}


def save_accounts():
    try:
        tmp = ACCOUNTS_PATH + ".tmp"
        with _accounts_lock:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(_accounts, f, indent=2)
        os.replace(tmp, ACCOUNTS_PATH)
    except Exception as e:
        print(f"[accounts] save error: {e}")


def new_account(name, sprite, salt, pw_hash):
    acc = {
        "id": secrets.token_hex(4).upper(),
        "name": name,
        "sprite": sprite or "SPRITE_RED",
        "salt": salt,
        "pwHash": pw_hash,
        "tokens": [secrets.token_hex(16)],
        "created": int(time.time()),
    }
    with _accounts_lock:
        _accounts[name.lower()] = acc
    save_accounts()
    return acc


def add_token(acc):
    token = secrets.token_hex(16)
    with _accounts_lock:
        acc.setdefault("tokens", []).append(token)
        acc["tokens"] = acc["tokens"][-5:]     # keep at most 5 devices
    save_accounts()
    return token


# ---------------------------------------------------------------------------
# Live players
# ---------------------------------------------------------------------------

_players = {}                  # accountId -> Player
_players_lock = threading.RLock()


class Player:
    __slots__ = ("pid", "name", "sprite", "map", "x", "y", "facing",
                 "conn", "send_lock", "last_seen", "alive")

    def __init__(self, pid, name, sprite, conn, send_lock):
        self.pid = pid
        self.name = name
        self.sprite = sprite or "SPRITE_RED"
        self.map = None
        self.x, self.y, self.facing = 0, 0, "down"
        self.conn = conn
        self.send_lock = send_lock
        self.last_seen = time.time()
        self.alive = True

    def as_field(self):
        return f"{self.pid},{self.name},{self.sprite},{self.x},{self.y},{self.facing}"


def send_line(conn, lock, line):
    try:
        with lock:
            conn.sendall((line + "\n").encode("utf-8"))
        return True
    except OSError:
        return False


# ---------------------------------------------------------------------------
# Per-connection handler
# ---------------------------------------------------------------------------

def handle_client(conn, addr):
    lock = threading.Lock()
    rfile = conn.makefile("r", encoding="utf-8", newline="\n")
    authed = False
    player = None
    pending = None             # account awaiting AUTH after LOGIN
    nonce = None

    def reply(line):
        return send_line(conn, lock, line)

    def finish_auth(acc, token):
        nonlocal authed, player
        p = Player(acc["id"], acc["name"], acc["sprite"], conn, lock)
        with _players_lock:
            old = _players.get(acc["id"])
            if old is not None:
                old.alive = False
                try:
                    old.conn.close()
                except OSError:
                    pass
            _players[acc["id"]] = p
        authed = True
        player = p
        reply(f"OK|{acc['id']}|{acc['name']}|{token}")
        print(f"[+] {acc['name']} ({acc['id']}) authed from {addr[0]}")

    try:
        for raw in rfile:
            line = raw.rstrip("\n")
            if not line:
                continue
            f = line.split("|")
            tag = f[0]

            if not authed:
                if tag == "HI":
                    continue
                elif tag == "REG" and len(f) >= 5:
                    name = clean(f[1])[:10]
                    if not name:
                        reply("ERR|NEED_FIELDS|name required"); continue
                    with _accounts_lock:
                        exists = name.lower() in _accounts
                    if exists:
                        reply("ERR|NAME_TAKEN|that name is taken"); continue
                    acc = new_account(name, clean(f[2], "SPRITE_RED"),
                                      clean(f[3]), clean(f[4]))
                    finish_auth(acc, acc["tokens"][-1])
                elif tag == "LOGIN" and len(f) >= 2:
                    with _accounts_lock:
                        acc = _accounts.get(clean(f[1]).lower())
                    if not acc:
                        reply("ERR|NO_ACCOUNT|no such trainer"); continue
                    pending = acc
                    nonce = secrets.token_hex(16)
                    reply(f"CHAL|{acc['salt']}|{nonce}")
                elif tag == "AUTH" and len(f) >= 2:
                    if not pending or not nonce:
                        reply("ERR|BAD_AUTH|no challenge in progress"); continue
                    expected = sha256_hex(pending["pwHash"] + nonce)
                    if clean(f[1]).lower() == expected.lower():
                        finish_auth(pending, add_token(pending))
                    else:
                        reply("ERR|BAD_AUTH|wrong passphrase")
                    pending, nonce = None, None
                elif tag == "TOK" and len(f) >= 3:
                    with _accounts_lock:
                        acc = _accounts.get(clean(f[1]).lower())
                    tok = clean(f[2])
                    if acc and tok in acc.get("tokens", []):
                        finish_auth(acc, tok)
                    else:
                        reply("ERR|BAD_TOKEN|token not recognised")
                elif tag == "B":
                    break
                else:
                    reply("ERR|PROTO|expected auth")
            else:
                if tag == "P" and len(f) >= 5:
                    player.map = clean(f[1]) or None
                    try:
                        player.x, player.y = int(f[2]), int(f[3])
                    except ValueError:
                        continue
                    player.facing = clean(f[4], "down")
                    player.last_seen = time.time()
                elif tag == "B":
                    break
    except OSError:
        pass
    finally:
        if player is not None:
            with _players_lock:
                if _players.get(player.pid) is player:
                    del _players[player.pid]
            print(f"[-] {player.name} ({player.pid}) disconnected")
        try:
            conn.close()
        except OSError:
            pass


# ---------------------------------------------------------------------------
# Broadcaster
# ---------------------------------------------------------------------------

def broadcaster():
    while True:
        time.sleep(TICK_SECONDS)
        now = time.time()
        with _players_lock:
            for pid in [p for p, pl in _players.items()
                        if not pl.alive or now - pl.last_seen > STALE_AFTER_SECONDS]:
                stale = _players.pop(pid, None)
                if stale:
                    stale.alive = False
                    try:
                        stale.conn.close()
                    except OSError:
                        pass
            snapshot = list(_players.values())

        by_map = {}
        for p in snapshot:
            if p.map is not None:
                by_map.setdefault(p.map, []).append(p)

        for p in snapshot:
            if p.map is None:
                continue
            peers = ";".join(q.as_field() for q in by_map.get(p.map, ())
                             if q.pid != p.pid)
            send_line(p.conn, p.send_lock, f"S|{p.map}|{peers}")


def status_printer():
    """Prints who's currently connected every few seconds - a live console
    view for testing, so you don't have to guess whether a client is really
    online and where. Purely diagnostic; does not affect the protocol."""
    while True:
        time.sleep(5.0)
        now = time.time()
        with _players_lock:
            snapshot = list(_players.values())
        if not snapshot:
            print("[status] nobody connected")
            continue
        for p in snapshot:
            where = f"{p.map} ({p.x},{p.y}) facing {p.facing}" if p.map else "NO POSITION YET"
            age = now - p.last_seen
            print(f"[status] {p.name} ({p.pid}) - {where} - last update {age:.1f}s ago")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="SilphNet relay server")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", 7788)))
    args = ap.parse_args()

    load_accounts()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.host, args.port))
    srv.listen(64)

    threading.Thread(target=broadcaster, daemon=True).start()
    threading.Thread(target=status_printer, daemon=True).start()

    print("=" * 62)
    print(" SilphNet relay server  (Milestone 1 + Phase 1 accounts)")
    print(f" Listening on {args.host}:{args.port}   protocol v{PROTOCOL_VERSION}")
    print(f" Accounts: {len(_accounts)} known   file: {ACCOUNTS_PATH}")
    print("=" * 62)

    try:
        while True:
            conn, addr = srv.accept()
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            threading.Thread(target=handle_client, args=(conn, addr),
                             daemon=True).start()
    except KeyboardInterrupt:
        print("\n[SilphNet] shutting down.")
    finally:
        srv.close()


if __name__ == "__main__":
    main()
