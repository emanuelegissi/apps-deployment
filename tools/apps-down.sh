#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

log "Stopping containers"
sd stop "${UNITS[@]}" || true

log "Stopping network: ${NET_UNIT}"
sd stop "${NET_UNIT}" || true

