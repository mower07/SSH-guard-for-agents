#!/bin/bash
source /root/.env_secrets

PENDING_DIR="/root/scripts/security/pending"
WHITELIST="/root/scripts/security/whitelist-ips.conf"

[ -d "$PENDING_DIR" ] || exit 0

for f in "$PENDING_DIR"/*.pending; do
  [ -f "$f" ] || continue

  IFS='|' read -r IP HOST SERVER_LABEL SERVER_IP < "$f"
  AGE=$(( $(date +%s) - $(stat -c %Y "$f") ))

  if [ "$AGE" -gt 300 ]; then
    # Заблокировать IP
    sudo ufw insert 1 deny from "$IP" to any 2>/dev/null

    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TG_OWNER_ID}" \
      --data-urlencode "text=🚨 ЗАБЛОКИРОВАН <code>${IP}</code> на ${SERVER_LABEL} | <b>${HOST}</b>
Причина: нет ответа 5 минут.
Разблокировать: <code>ufw delete deny from ${IP}</code>" \
      -d "parse_mode=HTML" \
      > /dev/null 2>&1

    rm "$f"
  fi
done
