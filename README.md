🇺🇸 English | [🇷🇺 Русский](README.ru.md)

# SSH Guard — Server Monitoring & Protection via Telegram

A set of bash scripts for VPS and dedicated servers running Ubuntu/Debian.
Notifies you in Telegram on every SSH login, batches messages intelligently, and auto-blocks unknown IPs.

---

## Who It's For

- Developers and sysadmins running one or more VPS
- Teams with multiple servers, agents, workstations, or employees
- Anyone who wants real-time alerts on suspicious logins — without manual log checks

---

## What's Inside

### Smart SSH Login Alerts
- **Known IP** → logins are queued, one batched message per minute:
  ```
  🔐 3 SSH logins on MyServer | myserver (1.2.3.4)
  10:00:01 — 10:00:48
    • Admin (1.2.3.4) — root — 10:00:01
    • RemoteAgent (5.6.7.8) — root — 10:00:32
  ```
- **Unknown IP, first login** → instant alert + YES/NO prompt + 5-minute timeout
- **Unknown IP, repeat login** → **immediate auto-ban** without waiting
- **No response in 5 minutes** → IP is automatically blocked via UFW

### Service Monitoring
Checks that services are alive every 5 minutes. If one goes down — sends a Telegram alert.

### Disk & Memory Monitoring
Alerts when disk usage exceeds 80% or memory exceeds 90%.

### Anomalous Port Detection
Compares open ports against a baseline once a day. If a new port appears — sends an alert.

### Multi-Server Support
Single shared IP whitelist for all servers. Adding a new server takes one command.

---

## Requirements

- Ubuntu/Debian with UFW
- Telegram bot (create via @BotFather, save the token)
- SSH access to the server with a key (passwordless)
- One server designated as **master** (stores shared whitelist and syncs to others)

---

## Quick Start

### 1. Create a Telegram Bot
- Message @BotFather → `/newbot`
- Save the bot token
- Get your Telegram chat ID: message @userinfobot

### 2. Fill in `.env_secrets`
```bash
cp scripts/.env_secrets.template /root/.env_secrets
nano /root/.env_secrets
chmod 600 /root/.env_secrets
```

### 3. Deploy on the Master Server
```bash
mkdir -p /root/scripts/security/pending
cp scripts/*.sh /root/scripts/security/
cp scripts/*.conf /root/scripts/security/
chmod 700 /root/scripts/security/*.sh

# SSH alert via PAM
echo 'session optional pam_exec.so /root/scripts/security/ssh-alert.sh' >> /etc/pam.d/sshd

# Cron jobs
(crontab -l 2>/dev/null; \
  echo "*/5 * * * * /root/scripts/security/monitor.sh"; \
  echo "0 8 * * * /root/scripts/security/port-check.sh"; \
  echo "* * * * * /root/scripts/security/pending-check.sh"; \
  echo "* * * * * /root/scripts/security/send-queue.sh"; \
  echo "0 3 * * * /root/scripts/security/sync-whitelist.sh") | crontab -
```

### 4. Add Your IP to the Whitelist
```bash
echo "1.2.3.4 Admin" >> /root/scripts/security/whitelist-ips.conf
```

### 5. Allow UFW Without Password (if running as non-root)
```bash
echo "myuser ALL=(ALL) NOPASSWD: /usr/sbin/ufw" >> /etc/sudoers.d/myuser-ufw
chmod 440 /etc/sudoers.d/myuser-ufw
```

### 6. Onboard a New Server
```bash
./onboard-server.sh root@IP "Label"
```

---

## Unknown IP Blocking Logic

```
Unknown IP connects
        │
        ▼
First time? ──Yes──▶ Alert + create pending file
        │                   │
        │             Waiting for response
        │            YES ◀──┤──▶ NO / 5 min timeout
        │             │              │
        │      Add to whitelist   Block IP
        │                         ufw deny from IP
        │
       No (pending already exists)
        │
        ▼
   Immediate ban 🚫
```

---

## Multi-Server & Multi-Agent Setup

### Architecture

```
Master server (stores whitelist)
├── /root/scripts/security/whitelist-ips.conf  ← single source of truth
├── /root/scripts/security/servers.conf        ← list of servers
└── cron: sync-whitelist.sh daily → pushes to all servers

Server-2, Server-3, ..., Server-N
└── /root/scripts/security/whitelist-ips.conf  ← received from master
```

### Add a New Server (from master)
```bash
./onboard-server.sh root@NEW_IP "Prod-Backend"
```

### Multiple Workstations for One Person
```bash
echo "1.2.3.4 Admin-home" >> /root/scripts/security/whitelist-ips.conf
echo "5.6.7.8 Admin-office" >> /root/scripts/security/whitelist-ips.conf
echo "9.10.11.12 Admin-mobile" >> /root/scripts/security/whitelist-ips.conf
```

### Multiple Team Members
```bash
echo "1.2.3.4 Ivan" >> whitelist-ips.conf
echo "5.6.7.8 Maria-home" >> whitelist-ips.conf
echo "13.14.15.16 Alexey" >> whitelist-ips.conf
```

### 10 Bots / AI Agents
```bash
echo "10.0.0.1 Agent-1" >> whitelist-ips.conf
echo "10.0.0.2 Agent-2" >> whitelist-ips.conf
# After adding — sync to all servers:
bash /root/scripts/security/sync-whitelist.sh
```

---

## Configuration

`ssh-alert.sh` — server label in notifications:
```bash
SERVER_LABEL="MyServer"
```

`monitor.sh` — list of services to monitor:
```bash
SERVICES="nginx postgresql myapp"
```

---

## Troubleshooting

### Locked myself out — can't SSH in
1. Log in via your hosting provider's KVM/VNC console
2. Run: `ufw delete deny from YOUR_IP`
3. Add IP to whitelist: `echo "1.2.3.4 Admin" >> /root/scripts/security/whitelist-ips.conf`

### Same IP keeps triggering alerts twice
PAM sometimes opens two sessions. Check for duplicates:
```bash
grep "ssh-alert" /etc/pam.d/sshd
# If two lines — remove the duplicate:
sed -i '0,/ssh-alert/! {/ssh-alert/d}' /etc/pam.d/sshd
```

### Updated whitelist but server still asks
Sync manually:
```bash
bash /root/scripts/security/sync-whitelist.sh
```

### Agent/bot keeps triggering alerts
Add the agent's static IP to the whitelist. If the IP is dynamic — provision a static IP for the agent's server.

### Server blocked a legitimate IP
```bash
ufw delete deny from IP_ADDRESS
echo "IP_ADDRESS Label" >> /root/scripts/security/whitelist-ips.conf
bash /root/scripts/security/sync-whitelist.sh
```

---

## File Structure

```
scripts/
├── ssh-alert.sh          # PAM hook: alert + queue + auto-ban
├── send-queue.sh         # Batching: combines logins into one message
├── pending-check.sh      # Auto-block on timeout (5 min)
├── monitor.sh            # Service + disk + memory monitoring
├── port-check.sh         # Anomalous ports (daily)
├── sync-whitelist.sh     # Sync whitelist to all servers
├── onboard-server.sh     # Deploy to new server in one command
├── whitelist-ips.conf    # IP whitelist
├── servers.conf          # Server list for sync
└── .env_secrets.template # Token template (do not commit!)
```

---

## Known Limitations

- UFW block affects all traffic from an IP, not just SSH
- "YES" response (approve IP) still requires manually adding to whitelist
- `monitor.sh` — service list must be configured separately on each server
- Dynamic IPs (mobile, some ISPs) require manual whitelist updates
- One bot notifies one person; for teams — extend the scripts to support multiple chat IDs

---

Built in February 2026. Tested on Ubuntu 22.04 / 24.04.

## OpenClaw self-heal (systemd watchdog + timer)

This repository now includes a lightweight self-heal profile for OpenClaw services.

Files:
- `scripts/service-healthcheck.sh`
- `systemd/openclaw-healthcheck.service`
- `systemd/openclaw-healthcheck.timer`

Install (user-level systemd):
```bash
mkdir -p ~/.config/systemd/user
cp systemd/openclaw-healthcheck.service ~/.config/systemd/user/
cp systemd/openclaw-healthcheck.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now openclaw-healthcheck.timer
```

What it does:
- every 90s checks `openclaw-gateway.service`, `telegram-mcp.service`, `telegram-dm.service`
- if service is not active, restarts it
- anti-spam event logging (`~/.cache/openclaw-healthcheck/events.log`)
- no LLM calls, negligible CPU
