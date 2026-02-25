#!/usr/bin/env bash
set -euo pipefail

NET="apps"
MINIO_URL="http://minio:9000"
MC_IMG="docker.io/minio/mc:RELEASE.2025-07-21T05-28-08Z-cpuv1"
TIMEOUT_SEC=60

# Persist mc config (aliases) across podman run invocations
MC_CFG_DIR="${HOME}/.local/share/apps-deployment/persist/minio/mc"

die() { echo "ERROR: $*" >&2; exit 1; }

prompt() {
  local var="$1" label="$2" secret="${3:-0}" default="${4:-}"
  local val=""
  while [[ -z "$val" ]]; do
    if [[ "$secret" == "1" ]]; then
      # shellcheck disable=SC2162
      read -rsp "${label}${default:+ [$default]}: " val
      echo
    else
      # shellcheck disable=SC2162
      read -rp "${label}${default:+ [$default]}: " val
    fi
    [[ -z "$val" && -n "$default" ]] && val="$default"
    [[ -z "$val" ]] && echo "Value cannot be empty."
  done
  printf -v "$var" '%s' "$val"
}

# Basic bucket name sanity check (not perfect S3 validation, but catches common mistakes)
valid_bucket_name() {
  local b="$1"
  [[ ${#b} -ge 3 && ${#b} -le 63 ]] || return 1
  [[ "$b" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] || return 1
  [[ "$b" != *".."* ]] || return 1
  [[ "$b" != *".-"* && "$b" != *"-."* ]] || return 1
  return 0
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }
need_cmd podman
need_cmd mkdir

mkdir -p "$MC_CFG_DIR"

mc() {
  # Mount a persistent config dir so aliases survive across runs
  podman run --rm --network "$NET" \
    -v "${MC_CFG_DIR}:/root/.mc:Z" \
    "$MC_IMG" "$@"
}

echo "MinIO init (network: $NET, url: $MINIO_URL)"
echo "mc config dir: $MC_CFG_DIR"
echo

prompt MINIO_ROOT_USER      "MINIO_ROOT_USER"
prompt MINIO_ROOT_PASSWORD  "MINIO_ROOT_PASSWORD" 1
prompt MINIO_DEFAULT_BUCKET "MINIO_DEFAULT_BUCKET"

if ! valid_bucket_name "$MINIO_DEFAULT_BUCKET"; then
  die "Bucket name '$MINIO_DEFAULT_BUCKET' looks invalid. Use 3-63 chars, lowercase letters/digits, '.' or '-', no leading/trailing '.'/'-'."
fi

echo
echo "Waiting for MinIO (up to ${TIMEOUT_SEC}s)..."

# Remove any stale alias (e.g., pointing to localhost) before setting
mc alias rm local >/dev/null 2>&1 || true

for ((i=1; i<=TIMEOUT_SEC; i++)); do
  if mc alias set local "$MINIO_URL" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; then
    break
  fi
  if [[ "$i" -eq "$TIMEOUT_SEC" ]]; then
    die "MinIO not reachable or auth failed after ${TIMEOUT_SEC}s (check minio.service, network '$NET', credentials)."
  fi
  sleep 1
done

# Optional: show what local points to (useful for debugging)
mc alias list 2>/dev/null | awk 'NR==1 || $1=="local" {print}'

echo "Creating bucket (idempotent): $MINIO_DEFAULT_BUCKET"
mc mb --ignore-existing "local/${MINIO_DEFAULT_BUCKET}" >/dev/null

echo "Enabling versioning (best-effort): $MINIO_DEFAULT_BUCKET"
mc version enable "local/${MINIO_DEFAULT_BUCKET}" >/dev/null 2>&1 || true

mc ls "local/${MINIO_DEFAULT_BUCKET}" >/dev/null
echo "OK: Bucket ready: ${MINIO_DEFAULT_BUCKET} (versioning enabled)"

