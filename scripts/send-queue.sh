#!/bin/bash
# Обрабатывает очередь известных SSH-входов, отправляет пачкой
source /root/.env_secrets

QUEUE_FILE="/root/scripts/security/ssh-queue.txt"
LOCK_FILE="/root/scripts/security/queue.lock"

# Если очередь пуста — выйти
[ -f "$QUEUE_FILE" ] && [ -s "$QUEUE_FILE" ] || exit 0

# Захватить файл атомарно (swap)
TEMP_FILE="${QUEUE_FILE}.processing"
mv "$QUEUE_FILE" "$TEMP_FILE" 2>/dev/null || exit 0

COUNT=$(wc -l < "$TEMP_FILE")

if [ "$COUNT" -eq 1 ]; then
  # Один вход — обычный алерт
  IFS='|' read -r SERVER_LABEL HOST SERVER_IP PAM_USER PAM_RHOST LABEL DATE < "$TEMP_FILE"
  MSG="🔐 SSH вход на ${SERVER_LABEL} | <b>${HOST}</b> (<code>${SERVER_IP}</code>)
Пользователь: <code>${PAM_USER}</code>
Откуда: ${LABEL} (<code>${PAM_RHOST}</code>)
Время: ${DATE}"
else
  # Несколько входов — пачка
  FIRST_LINE=$(head -1 "$TEMP_FILE")
  IFS='|' read -r SERVER_LABEL HOST SERVER_IP _ _ _ _ <<< "$FIRST_LINE"
  FIRST_TIME=$(awk -F'|' 'NR==1{print $7}' "$TEMP_FILE")
  LAST_TIME=$(awk -F'|' 'END{print $7}' "$TEMP_FILE")

  ENTRIES=""
  while IFS='|' read -r SL H SIP USER RHOST LBL DT; do
    ENTRIES="${ENTRIES}  • ${LBL} (<code>${RHOST}</code>) — <code>${USER}</code> — ${DT}\n"
  done < "$TEMP_FILE"

  MSG="🔐 <b>${COUNT} SSH-входов</b> на ${SERVER_LABEL} | <b>${HOST}</b> (<code>${SERVER_IP}</code>)
${FIRST_TIME} — ${LAST_TIME}

$(echo -e "$ENTRIES")"
fi

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TG_OWNER_ID}" \
  --data-urlencode "text=${MSG}" \
  -d "parse_mode=HTML" \
  > /dev/null 2>&1

rm -f "$TEMP_FILE"
