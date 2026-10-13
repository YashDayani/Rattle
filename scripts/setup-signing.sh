#!/usr/bin/env bash
# Creates a stable self-signed code-signing identity ("Rattle Local Signing") in the login keychain.
# Signing every build with it keeps the app's designated requirement constant, so macOS keeps
# the Microphone / Accessibility grants across rebuilds.
set -euo pipefail
NAME="Rattle Local Signing"
KC="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KC" | grep -q "$NAME"; then
  echo "Identity '$NAME' already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -r "$TMP"' EXIT
cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/openssl.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="rattle-$RANDOM$RANDOM"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout "pass:$PASS" -out "$TMP/id.p12"
security import "$TMP/id.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign
# Trust the cert for code signing (macOS may ask for your login password once).
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem" || \
  echo "Note: could not set trust automatically; signing by name still works."
echo "Created identity '$NAME'."
