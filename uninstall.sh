#!/usr/bin/env bash
set -euo pipefail

# apps-deployment uninstall script
#
# Default (non-destructive):
#   - Removes symlinks:
#       ~/.config/containers/systemd/*.container|*.network|*.volume|*.kube
#       ~/apps-config
#   - Keeps persist unless --purge is passed
#
# Destructive mode (--purge):
#   - Also deletes:
#       ~/apps-persist
#
# Secrets are never deleted

# Distribution
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
QUADLETS_DIR="${REPO_DIR}/quadlets"

# Local install dirs
CONFIG_DIR="${HOME}/apps-config"
SECRETS_DIR="${HOME}/apps-secrets"
PERSIST_DIR="${HOME}/apps-persist"
QUADLET_USER_DIR="${HOME}/.config/containers/systemd"

# Flags
PURGE=0
FORCE=0

log()  { printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\n\033[1;31m[err]\033[0m %s\n" "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [--purge] [--force]

  --purge           Remove persistence data too (DESTRUCTIVE)
  --force           Do not prompt for confirmation

Default behavior keeps secrets + persist (non-destructive).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

confirm() {
  local msg="$1"
  if [[ "$FORCE" -eq 1 ]]; then
    return 0
  fi
  read -r -p "${msg} [y/N] " ans </dev/tty
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

log "Check needed commands"
need_cmd systemctl
need_cmd readlink
need_cmd mkdir
need_cmd rm

log "Stopping quadlet services"
systemctl --user stop '*.container' 2>/dev/null || true

log "Removing quadlet symlinks: ${QUADLET_USER_DIR}"
if [[ -d "${QUADLET_USER_DIR}" ]]; then
  find "${QUADLET_USER_DIR}" -maxdepth 1 -type l \( \
    -name '*.container' -o -name '*.network' -o -name '*.volume' -o -name '*.kube' \
  \) -exec rm -f {} +
fi

log "Removing config symlink: ${CONFIG_DIR}"
if [[ -L "${CONFIG_DIR}" ]]; then
  rm -f "${CONFIG_DIR}"
fi

log "Reloading systemd --user"
systemctl --user daemon-reload || true
systemctl --user reset-failed || true

if [[ "$PURGE" -eq 1 ]]; then
  warn "PURGE enabled: persistence data will be deleted."
  if confirm "Proceed with deleting ${PERSIST_DIR}?"; then
    sudo rm -rf "${PERSIST_DIR}"
  else
    warn "Purge cancelled; leaving persistence data intact."
  fi
else
  log "Keeping persistence data (use --purge to remove)."
fi

log "Clean complete."
cat <<EOF

Remaining (if any):
  Secrets:    ${SECRETS_DIR}      $( [[ -d "${SECRETS_DIR}" ]] && echo "(kept)" || echo "(removed)" )
  Persist:    ${PERSIST_DIR}      $( [[ -d "${PERSIST_DIR}" ]] && echo "(kept)" || echo "(removed)" )

EOF

