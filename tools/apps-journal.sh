#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

unit="${1:-}"
if [[ -z "$unit" ]]; then
  echo "Usage: $(basename "$0") <unit>"
  echo
  echo "Available units:"
  units_ordered || true
  exit 1
fi

jc -u "$unit" -e --no-pager
