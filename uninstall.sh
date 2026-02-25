#!/usr/bin/env bash
set -euo pipefail

# apps-deployment uninstall script
#
# Default (non-destructive):
#   - Removes symlinks that point into THIS repo:
#       ~/.config/containers/systemd/*.container|*.network|*.volume|*.kube
#       ~/apps-config                     (if it points into this repo)
#   - Keeps secrets + persist unless --purge is passed
#
# Destructive mode (--purge):
#   - Also deletes:
#       ~/apps-secrets
#       ~/apps-persist

# Distribution
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
QUADLETS_DIR="${REPO_DIR}/quadlets"

# Local install dirs
CONFIG_DIR="${HOME}/apps-config"
SECRETS_DIR="${HOME}/apps-secrets"
SECRETS_FILE="${SECRETS_DIR}/apps-secrets.env"
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

  --purge           Remove secrets and persistence data too (DESTRUCTIVE)
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
  read -r -p "${msg} [y/N] " ans
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

log "Check needed commands"
need_cmd systemctl
need_cmd readlink
need_cmd mkdir
need_cmd rm
need_cmd rmdir

# Remove quadlet symlinks in ~/.config/containers/systemd that point into THIS repo.
# This avoids deleting other unrelated quadlets the user might have.

log "Removing quadlet symlinks pointing into this repo from: ${QUADLET_USER_DIR}"
mkdir -p "${QUADLET_USER_DIR}"

shopt -s nullglob
for link in "${QUADLET_USER_DIR}"/*.container "${QUADLET_USER_DIR}"/*.network "${QUADLET_USER_DIR}"/*.volume "${QUADLET_USER_DIR}"/*.kube; do
  [[ -L "$link" ]] || continue
  target="$(readlink -f "$link" 2>/dev/null || true)"
  if [[ -n "$target" && "$target" == "${REPO_DIR}/"* ]]; then
    rm -f "$link"
  fi
done
shopt -u nullglob

# Remove config symlink if it points into THIS repo.

log "Removing config symlink (only if it points into this repo)"
if [[ -L "${CONFIG_DIR}" ]]; then
  target="$(readlink -f "${CONFIG_DIR}" 2>/dev/null || true)"
  if [[ -n "$target" && "$target" == "${REPO_DIR}/config/"* ]]; then
    rm -f "${CONFIG_DIR}"
  else
    warn "Config link exists but does not point into this repo; leaving it: ${CONFIG_DIR}"
  fi
fi

# Reload systemd --user to drop generated units / reset failed state.

log "Reloading systemd --user"
systemctl --user daemon-reload || true
systemctl --user reset-failed || true

# Optionally purge secrets + persist (DESTRUCTIVE).

if [[ "$PURGE" -eq 1 ]]; then
  warn "PURGE enabled: secrets and persistence data will be deleted."
  if confirm "Proceed with deleting ${SECRETS_DIR} and ${PERSIST_DIR}?"; then
    sudo rm -rf "${SECRETS_DIR}" "${PERSIST_DIR}"
  else
    warn "Purge cancelled; leaving secrets and persistence data intact."
  fi
else
  log "Keeping secrets and persistence data (use --purge to remove)."
fi

log "Clean complete."
cat <<EOF

Remaining (if any):
  Secrets:    ${SECRETS_DIR}      $( [[ -d "${SECRETS_DIR}" ]] && echo "(kept)" || echo "(removed)" )
  Persist:    ${PERSIST_DIR}      $( [[ -d "${PERSIST_DIR}" ]] && echo "(kept)" || echo "(removed)" )

Quadlet dir:
  ${QUADLET_USER_DIR}

EOF

