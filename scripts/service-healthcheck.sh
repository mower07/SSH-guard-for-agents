#!/usr/bin/env bash
set -euo pipefail

# lightweight service self-heal for OpenClaw stack
# usage:
#   ./scripts/service-healthcheck.sh
#   SERVICES="openclaw-gateway.service telegram-mcp.service telegram-dm.service" ./scripts/service-healthcheck.sh

SERVICES_STR=${SERVICES:-"openclaw-gateway.service telegram-mcp.service telegram-dm.service"}
IFS=  read -r -a SERVICES <<< "$SERVICES_STR"

STATE_DIR=${STATE_DIR:-"$HOME/.cache/openclaw-healthcheck"}
LOG_FILE=${LOG_FILE:-"$STATE_DIR/events.log"}
THROTTLE_SEC=${THROTTLE_SEC:-900}
mkdir -p "$STATE_DIR"

now=$(date +%s)
for svc in "${SERVICES[@]}"; do
  active=$(systemctl --user is-active "$svc" 2>/dev/null || true)
  if [[ "$active" != "active" ]]; then
    stamp_file="$STATE_DIR/${svc}.last"
    last=0
    [[ -f "$stamp_file" ]] && last=$(cat "$stamp_file" 2>/dev/null || echo 0)

    if (( now - last >= THROTTLE_SEC )); then
      printf "%s service=%s state=%s action=restart\n" "$(date -Is)" "$svc" "$active" >> "$LOG_FILE"
      echo "$now" > "$stamp_file"
    fi

    systemctl --user restart "$svc" || true
  fi
done
