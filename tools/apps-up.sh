#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

log "Daemon reload"
sd daemon-reload

log "Starting network: ${NET_UNIT}"
sd start "${NET_UNIT}" || warn "Could not start ${NET_UNIT} (may not exist)."

log "Starting containers"
sd start "${UNITS[@]}"

log "Status"
sd status --no-pager "${NET_UNIT}" "${UNITS[@]}" || true

