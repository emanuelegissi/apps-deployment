#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

log "Failed user units:"
sd --failed --no-pager || true

echo
log "Recent errors (journald priority=err):"
jc -p err -n 100 --no-pager || true
