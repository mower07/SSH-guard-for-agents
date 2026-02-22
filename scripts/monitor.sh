#!/bin/bash
source ~/scripts/security/.env_secrets

# Нужно для systemctl --user в cron (нет D-Bus сессии)
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus

HOST=$(hostname -s)
ALERTS=""

# === User сервисы ===
SERVICES="telegram-mcp.service telegram-dm.service openclaw-gateway.service"
for svc in $SERVICES; do
  status=$(systemctl --user is-active "$svc" 2>/dev/null)
  if [ "$status" != "active" ]; then
    ALERTS="${ALERTS}⚠️ Сервис <b>${svc}</b>: ${status}\n"
  fi
done

# === Диск ===
DISK_USE=$(df / --output=pcent | tail -1 | tr -d ' %')
if [ "$DISK_USE" -gt 80 ]; then
  DISK_INFO=$(df -h / | tail -1)
  ALERTS="${ALERTS}💾 Диск / заполнен на <b>${DISK_USE}%</b>\n  ${DISK_INFO}\n"
fi

# === Память ===
MEM_PCT=$(free -m | awk '/^Mem:/{printf "%.0f", ($3/$2)*100}')
if [ "$MEM_PCT" -gt 90 ]; then
  MEM_DETAIL=$(free -h | awk '/^Mem:/{print $3"/"$2}')
  ALERTS="${ALERTS}🧠 Память: <b>${MEM_PCT}%</b> (${MEM_DETAIL})\n"
fi

# Отправить только если есть алерты
if [ -n "$ALERTS" ]; then
  DATE=$(date '+%d.%m.%Y %H:%M')
  MSG="🚨 <b>${HOST}</b> — проблемы (${DATE}):\n\n${ALERTS}"
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TG_OWNER_ID}" \
    --data-urlencode "text=$(echo -e "$MSG")" \
    -d "parse_mode=HTML" \
    > /dev/null 2>&1
fi
