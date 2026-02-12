#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

mapfile -t UNITS < <(units_ordered)
if [[ ${#UNITS[@]} -eq 0 ]]; then
  warn "No quadlet units discovered in: $QUADLET_DIR"
  exit 0
fi

log "Restarting units"
sd restart "${UNITS[@]}"

log "Status"
sd status --no-pager "${UNITS[@]}" || true
