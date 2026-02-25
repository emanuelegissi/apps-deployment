#!/usr/bin/env bash
set -euo pipefail

# apps-deployment install script
#
# Repository structure (git working tree):
#
#   apps-deployment/                 REPO_DIR
#     install.sh                     this installer
#     quadlets/                      Podman Quadlet unit files (e.g. *.container, *.network)
#     config/                        configuration files referenced by quadlets
#     secrets/
#       apps-secrets.env.template    secrets env template (safe to commit)
#     tools/                         convenience scripts
#     www-template/                  optional static website template files
#
# The local deployment directories are:
#     ~/apps-config/                 CONFIG_DIR, a sym link to <REPO_DIR>/config
#     ~/apps-secrets/                SECRETS_DIR
#     ~/apps-persist/                PERSIST_DIR
#         caddy-data/                   caddy server data
#         caddy-state/                  caddy server state
#         dex/                          dex data
#         grist/                        grist data
#         minio/                        minio data
#         n8n/                          n8n data
#         redis/                        redis data
#         www/                          static website
#       .config/containers/systemd/  sym links to quadlets
#
# After creating the dirs, this installer:
#
# - creates the secrets env file once by copying from the repo template (if missing):
#     ~/apps-secrets/apps-secrets.env
#   and enforces permissions: chmod 600.
#   The secrets file is intentionally NOT a symlink so it remains host-specific
#   and stays untracked by git.
#
# - optionally populates the website persistence directory from www-template:
#     rsync <REPO_DIR>/www-template/.  ->  ~/apps-persist/www/
#
# - creates symlinks for all quadlet unit files into:
#     ~/.config/containers/systemd/
#   so editing quadlets in the repo updates the deployed units immediately.
#   Then runs: systemctl --user daemon-reload
#
# Re-running the installer is safe and re-links quadlets, and config;
# it does not overwrite existing secrets.
# 
# After installing, run minio-init.sh tool to create the minio bucket.


# Distribution
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
QUADLETS_DIR="${REPO_DIR}/quadlets"
REPO_CONFIG_DIR="${REPO_DIR}/config"
WWW_TEMPLATE_DIR="${REPO_DIR}/www-template"
SECRETS_TEMPLATE="${REPO_DIR}/secrets/apps-secrets.env.template"

# Local install dirs
CONFIG_DIR="${HOME}/apps-config"
SECRETS_DIR="${HOME}/apps-secrets"
SECRETS_FILE="${SECRETS_DIR}/apps-secrets.env"
PERSIST_DIR="${HOME}/apps-persist"
PERSIST_SUBDIRS=(
  "caddy-data"
  "caddy-state"
  "dex"
  "grist"
  "minio"
  "n8n"
  "redis"
  "www"
)
QUADLET_USER_DIR="${HOME}/.config/containers/systemd"

# Tools
log()  { printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\n\033[1;31m[err]\033[0m %s\n" "$*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

log "Check needed commands"
need_cmd mkdir
need_cmd ln
need_cmd find
need_cmd readlink
need_cmd rsync
need_cmd systemctl
need_cmd chmod
need_cmd podman

log "Check distribution"
[[ -d "${QUADLETS_DIR}" ]] || die "Missing: ${QUADLETS_DIR}"
[[ -d "${REPO_CONFIG_DIR}" ]] || die "Missing: ${REPO_CONFIG_DIR}"
[[ -f "${SECRETS_TEMPLATE}" ]] || die "Missing secrets template: ${SECRETS_TEMPLATE}"

log "Symlink config to repo (editable in git working tree)"
if [[ -e "${CONFIG_DIR}" && ! -L "${CONFIG_DIR}" ]]; then
  warn "${CONFIG_DIR} exists and is not a symlink; not overwriting."
else
  ln -sfn "${REPO_CONFIG_DIR}" "${CONFIG_DIR}"
fi

log "Create base directories"
mkdir -p "${SECRETS_DIR}" "${PERSIST_DIR}" "${QUADLET_USER_DIR}"

log "Create persistence subfolders"
for d in "${PERSIST_SUBDIRS[@]}"; do
  mkdir -p "${PERSIST_DIR}/${d}"
done

log "Install secrets env file from template (create if missing)"
if [[ ! -f "${SECRETS_FILE}" ]]; then
  rsync -a "${SECRETS_TEMPLATE}" "${SECRETS_FILE}"
fi
chmod 600 "${SECRETS_FILE}"

log "Populate www from www-template"
if [[ -d "${WWW_TEMPLATE_DIR}" ]]; then
  rsync -a --ignore-existing "${WWW_TEMPLATE_DIR}/." "${PERSIST_DIR}/www/"
else
  warn "Missing: ${WWW_TEMPLATE_DIR} (skipping www population)"
fi

log "Remove stale quadlet symlinks from ${QUADLET_USER_DIR}"
find "${QUADLET_USER_DIR}" -maxdepth 1 -type l \( \
  -name '*.container' -o -name '*.network' -o -name '*.volume' -o -name '*.kube' \
\) 2>/dev/null | while read -r l; do
  [[ ! -e "$l" ]] && rm -f "$l"
done

log "Symlink quadlets into ${QUADLET_USER_DIR}"
shopt -s nullglob
quadlet_files=( "${QUADLETS_DIR}"/*.container "${QUADLETS_DIR}"/*.network "${QUADLETS_DIR}"/*.volume "${QUADLETS_DIR}"/*.kube )
shopt -u nullglob
[[ ${#quadlet_files[@]} -gt 0 ]] || die "No quadlets found in ${QUADLETS_DIR}"

for f in "${quadlet_files[@]}"; do
  ln -sfn "$f" "${QUADLET_USER_DIR}/$(basename "$f")"
done

log "Reload user systemd generator"
systemctl --user daemon-reload
systemctl --user reset-failed || true

log "Done."
cat <<EOF

Configuration: ${CONFIG_DIR}
Secrets: ${SECRETS_DIR}
Persistence: ${PERSIST_DIR}
Podman quadlets: ${QUADLET_USER_DIR}

Enable linger for the current user so systemd --user units
can start at boot without an interactive login with:
  sudo loginctl enable-linger ${USER}

Run minio-init.sh tool to create the minio bucket,
and activate minio for grist in its quadlet.

EOF
