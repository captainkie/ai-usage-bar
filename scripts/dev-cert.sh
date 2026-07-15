#!/usr/bin/env bash
# Create a stable self-signed code-signing certificate so the app keeps a
# consistent identity across rebuilds. That makes macOS remember your
# "Always Allow" Keychain choice permanently (ad-hoc signing changes identity
# on every rebuild, so the prompt keeps coming back).
#
# Run once:  ./scripts/dev-cert.sh
set -euo pipefail

CERT_NAME="${1:-AI Usage Bar Self-Signed}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Note: use `-p codesigning` WITHOUT `-v`; a self-signed cert is untrusted
# (CSSMERR_TP_NOT_TRUSTED) so `-v` hides it, but codesign can still use it.
if security find-identity -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
    echo "==> Signing identity already exists: $CERT_NAME"
    exit 0
fi

echo "==> Creating self-signed code-signing certificate: $CERT_NAME"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cfg.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CERT_NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg.cnf" 2>/dev/null

# Use a throwaway password + legacy PBE: modern OpenSSL 3 defaults produce a
# PKCS#12 MAC that macOS `security import` rejects ("MAC verification failed").
PW="aiusagebar-import"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:"$PW" -name "$CERT_NAME" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES 2>/dev/null

# Import the identity and pre-authorize codesign to use the private key.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PW" -T /usr/bin/codesign

echo "==> Done. Installed identity:"
security find-identity -p codesigning | grep -F "$CERT_NAME" || {
    echo "!! Certificate not found after import." >&2
    exit 1
}
