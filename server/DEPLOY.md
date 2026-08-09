# Deploying the SilphNet server on a cheap Linux VPS

The relay is a single, dependency-free Python file. Any small Ubuntu VPS runs
it comfortably — **1 vCPU / 1 GB RAM is plenty to start** (you + mates, and
realistically a few dozen players). See "Scaling" below for what to do as it
grows.

> Read [SECURITY.md](../SECURITY.md) first. In its current form the server has
> **no authentication** — anyone who knows the address can connect and claim any
> trainer id. That's fine on a LAN or a private address you only share with
> mates, but **add token auth before you let strangers sign up.**

## 1. Get a VPS

Provision a small **Ubuntu 22.04 or 24.04** VPS from whichever provider you
prefer. Note its **public IP**. You only need SSH access.

## 2. First-time setup

```bash
ssh root@YOUR_VPS_IP
adduser deploy && usermod -aG sudo deploy          # a normal admin user
apt update && apt upgrade -y
apt install -y python3 git ufw
adduser --system --group silphnet                  # unprivileged service user
```

## 3. Get the code onto the box

Because the repo is private, either add a read-only **deploy key** and
`git clone` it, or just copy the `server/` folder up with `scp`:

```bash
# from your PC:
scp -r server deploy@YOUR_VPS_IP:/tmp/silphnet-server
# on the VPS:
sudo mkdir -p /opt/silphnet
sudo mv /tmp/silphnet-server /opt/silphnet/server
sudo chown -R silphnet:silphnet /opt/silphnet
```

## 4. Run it as a service (auto-restart, survives reboot)

```bash
sudo cp /opt/silphnet/server/silphnet.service /etc/systemd/system/silphnet.service
sudo systemctl daemon-reload
sudo systemctl enable --now silphnet
systemctl status silphnet          # should say active (running)
journalctl -u silphnet -f          # live logs (Ctrl-C to stop watching)
```

## 5. Open the firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 7788/tcp            # the game port
sudo ufw enable
```

## 6. Point the mod at it

In the game's Mod Manager → SilphNet options, set **SERVER HOST** to the VPS
public IP and **SERVER PORT** to `7788`. Done.

## Keeping it healthy

- `sudo apt install unattended-upgrades` for automatic security updates.
- SSH: use keys, disable password login (`PasswordAuthentication no`).
- `sudo apt install fail2ban` to throttle SSH brute-force.
- Update the code later: `scp` the new files (or `git pull`), then
  `sudo systemctl restart silphnet`.

## Scaling (don't do this early — but here's the path)

The current server is deliberately simple: one thread per connection, an
in-memory world, a ~8 Hz broadcast. That's great up to roughly a few dozen —
low-hundreds concurrent on a small box.

When you actually approach that ceiling, in order:

1. **Vertical first** — bump the VPS to more RAM/CPU. Cheapest fix, buys a lot.
2. **Change the networking model** — swap thread-per-connection for `asyncio`
   (or rewrite the hot path in Go, one cheap goroutine per client). This is the
   real lever for hundreds+; I can do either when you need it.
3. **Interest management** — stop broadcasting a whole map to everyone; send
   each player only nearby trainers. Needed once single maps get crowded.
4. **Move position updates to UDP** — lower overhead than TCP for 8–20 Hz
   movement; keep TCP for logins/trades/battles.
5. **Shard** — split maps/regions across processes or boxes. Only relevant at
   a scale this project is unlikely to hit soon.

Milestone 1 doesn't need any of this. Start on the $-cheap box and grow into it.
