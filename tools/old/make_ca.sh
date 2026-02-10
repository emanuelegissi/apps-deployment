#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Generate a new Root CA + Intermediate CA (OpenSSL)
# Output dir is RELATIVE to the script location:
#   <script_dir>/../config/caddy/pki
# ============================================================

# Resolve script directory robustly (works with symlinks)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Relative output directory (relative to script location)
OUT_DIR="${SCRIPT_DIR}/../config/caddy/pki"

DAYS_ROOT=7300          # 20 years
DAYS_INTERMEDIATE=7300  # 20 years
KEY_BITS=4096

# Change these to match your org
ROOT_SUBJ="/C=IT/ST=Sardegna/L=Sassari/O=Vigili del Fuoco/OU=IT/CN=VVF Root CA"
INT_SUBJ="/C=IT/ST=Sardegna/L=Sassari/O=Vigili del Fuoco/OU=IT/CN=VVF Intermediate CA"

# If you want encrypted keys (requires manual passphrase entry), set to "yes"
ENCRYPT_KEYS="no"

umask 077

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found. Install it (e.g. 'sudo dnf install openssl')." >&2
    exit 1
  }
}

need openssl

mkdir -p "$OUT_DIR"

ROOT_KEY="$OUT_DIR/root.key"
ROOT_CRT="$OUT_DIR/root.crt"
INT_KEY="$OUT_DIR/intermediate.key"
INT_CSR="$OUT_DIR/intermediate.csr"
INT_CRT="$OUT_DIR/intermediate.crt"
INT_CHAIN="$OUT_DIR/intermediate-chain.crt"

ROOT_DIR="$OUT_DIR/root-ca"
INT_DIR="$OUT_DIR/intermediate-ca"

mkdir -p "$ROOT_DIR" "$INT_DIR"

# CA database files (used if you later sign leaf certs with openssl)
touch "$ROOT_DIR/index.txt" "$INT_DIR/index.txt"
echo 1000 > "$ROOT_DIR/serial"
echo 1000 > "$INT_DIR/serial"

chmod 700 "$OUT_DIR" "$ROOT_DIR" "$INT_DIR"
chmod 600 "$ROOT_DIR/index.txt" "$INT_DIR/index.txt" "$ROOT_DIR/serial" "$INT_DIR/serial"

# ---- OpenSSL config snippets (inline) ----
ROOT_EXT="$OUT_DIR/root_ext.cnf"
INT_EXT="$OUT_DIR/intermediate_ext.cnf"

cat > "$ROOT_EXT" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no

[ dn ]
# Filled via -subj

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:1
keyUsage = critical, keyCertSign, cRLSign
EOF

cat > "$INT_EXT" <<'EOF'
[ req ]
distinguished_name = dn
prompt = no

[ dn ]
# Filled via -subj

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
EOF

chmod 600 "$ROOT_EXT" "$INT_EXT"

gen_key() {
  local out="$1"
  if [[ "$ENCRYPT_KEYS" == "yes" ]]; then
    # Encrypted private key (you will be prompted for a passphrase)
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:"$KEY_BITS" -aes-256-cbc -out "$out"
  else
    # Unencrypted private key (best for unattended server use)
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:"$KEY_BITS" -out "$out"
  fi
  chmod 600 "$out"
}

echo "==> Script dir:  $SCRIPT_DIR"
echo "==> Output dir:  $OUT_DIR"
echo

echo "==> Generating Root CA private key..."
gen_key "$ROOT_KEY"

echo "==> Generating Root CA certificate..."
openssl req -x509 -new \
  -key "$ROOT_KEY" \
  -days "$DAYS_ROOT" \
  -sha256 \
  -subj "$ROOT_SUBJ" \
  -config "$ROOT_EXT" \
  -extensions v3_ca \
  -out "$ROOT_CRT"

chmod 644 "$ROOT_CRT"

echo "==> Generating Intermediate CA private key..."
gen_key "$INT_KEY"

echo "==> Creating Intermediate CA CSR..."
openssl req -new -sha256 \
  -key "$INT_KEY" \
  -subj "$INT_SUBJ" \
  -config "$INT_EXT" \
  -out "$INT_CSR"

echo "==> Signing Intermediate CA certificate with Root CA..."
openssl x509 -req -sha256 \
  -in "$INT_CSR" \
  -CA "$ROOT_CRT" \
  -CAkey "$ROOT_KEY" \
  -CAcreateserial \
  -days "$DAYS_INTERMEDIATE" \
  -extfile "$INT_EXT" \
  -extensions v3_intermediate_ca \
  -out "$INT_CRT"

chmod 644 "$INT_CRT"
rm -f "$INT_CSR"
rm -f "$OUT_DIR/root.srl" 2>/dev/null || true

echo "==> Writing intermediate chain (intermediate + root)..."
cat "$INT_CRT" "$ROOT_CRT" > "$INT_CHAIN"
chmod 644 "$INT_CHAIN"

echo
echo "DONE."
echo "Root CA:          $ROOT_CRT"
echo "Root key:         $ROOT_KEY"
echo "Intermediate CA:  $INT_CRT"
echo "Intermediate key: $INT_KEY"
echo "Chain file:       $INT_CHAIN"
echo
echo "Import the Root CA into client trust stores: $ROOT_CRT"

