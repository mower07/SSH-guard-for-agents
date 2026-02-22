#!/bin/bash
source /root/.env_secrets

HOST=$(hostname -s)
SERVER_LABEL="MyServer"
SERVER_IP=$(hostname -I | awk '{print $1}')
DATE=$(date '+%d.%m.%Y %H:%M:%S')
PAM_USER=${PAM_USER:-unknown}
PAM_RHOST=${PAM_RHOST:-local}
PAM_TYPE=${PAM_TYPE:-open_session}

if [ "$PAM_TYPE" != "open_session" ]; then exit 0; fi

WHITELIST="/root/scripts/security/whitelist-ips.conf"
PENDING_DIR="/root/scripts/security/pending"
QUEUE_FILE="/root/scripts/security/ssh-queue.txt"
mkdir -p "$PENDING_DIR"

send_msg() {
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TG_OWNER_ID}" \
    --data-urlencode "text=$1" \
    -d "parse_mode=HTML" \
    > /dev/null 2>&1
}

ban_ip() {
  local IP="$1"
  ufw insert 1 deny from "$IP" to any 2>/dev/null
  send_msg "🚫 СРАЗУ ЗАБЛОКИРОВАН <code>${IP}</code> на ${SERVER_LABEL} | <b>${HOST}</b>
Причина: повторный вход с неизвестного IP.
Время: ${DATE}
Разблокировать: <code>ufw delete deny from ${IP}</code>"
}

LABEL=$(grep "^${PAM_RHOST} " "$WHITELIST" 2>/dev/null | head -1 | awk '{$1=""; print $0}' | xargs)

if [ -n "$LABEL" ]; then
  # Известный IP → очередь
  echo "${SERVER_LABEL}|${HOST}|${SERVER_IP}|${PAM_USER}|${PAM_RHOST}|${LABEL}|${DATE}" >> "$QUEUE_FILE"
else
  SAFE_IP="${PAM_RHOST//\./_}"
  EXISTING_PENDING=$(ls "${PENDING_DIR}/"*"_${SAFE_IP}.pending" 2>/dev/null | head -1)

  if [ -n "$EXISTING_PENDING" ]; then
    # Уже было — повторный вход неизвестного IP → сразу бан
    ban_ip "$PAM_RHOST"
    rm -f "$EXISTING_PENDING"
  else
    # Первый раз — создать pending + спросить
    PENDING_FILE="${PENDING_DIR}/$(date +%s)_${SAFE_IP}.pending"
    echo "${PAM_RHOST}|${HOST}|${SERVER_LABEL}|${SERVER_IP}" > "$PENDING_FILE"

    send_msg "⚠️ НЕИЗВЕСТНЫЙ вход на ${SERVER_LABEL} | <b>${HOST}</b> (<code>${SERVER_IP}</code>)
Пользователь: <code>${PAM_USER}</code>
Откуда: <code>${PAM_RHOST}</code> ❓
Время: ${DATE}

Это ты? Ответь <b>ДА</b> — добавлю в белый список.
<b>НЕТ</b> или молчание 5 мин — заблокирую IP."
  fi
fi
