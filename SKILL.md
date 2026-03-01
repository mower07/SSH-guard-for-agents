---
name: ssh-guard-for-agents
description: "SSH monitoring and auto-protection for VPS servers. Telegram alerts on every login, IP whitelisting, auto-block of unknown IPs. Bash scripts + systemd. No external dependencies."
license: MIT
---

# SSH Guard for Agents

Real-time SSH monitoring and protection for VPS/dedicated servers (Ubuntu/Debian).
Sends Telegram alerts on every SSH login, batches messages intelligently, and auto-blocks unknown IPs.

## What it does

- **SSH alert** — instant Telegram notification on every SSH login (user, IP, timestamp)
- **IP whitelist** — known IPs are allowed silently; unknown IPs trigger alert + auto-block
- **Queue system** — batches rapid alerts to avoid Telegram flood limits
- **Health check** — periodic server status check via systemd timer
- **Multi-server sync** — sync whitelist across multiple servers

## Triggers

Use when asked to:
- Set up SSH monitoring on a new server
- Get Telegram alerts for SSH logins
- Auto-block unknown IPs

## Setup

```bash
# 1. Clone to server
git clone https://github.com/mower07/SSH-guard-for-agents.git /opt/ssh-guard

# 2. Configure
cp scripts/servers.conf.example scripts/servers.conf
# Fill in: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, whitelisted IPs

# 3. Install
bash scripts/onboard-server.sh

# 4. Enable systemd timer
systemctl enable --now openclaw-healthcheck.timer
```

## Files

- `scripts/ssh-alert.sh` — triggered by PAM on SSH login
- `scripts/monitor.sh` — main monitoring loop
- `scripts/send-queue.sh` — queued Telegram message sender
- `scripts/sync-whitelist.sh` — sync whitelist from central server
- `scripts/service-healthcheck.sh` — periodic health check
- `systemd/` — openclaw-healthcheck.service + .timer

## Requirements

- Ubuntu/Debian VPS
- Telegram bot token + chat ID
- bash, curl, jq

## связи
- [[server-management]]
