#!/bin/bash
# One-time: creates a self-signed "Nyx Dev" signing identity so the app's
# signature — and its Screen Recording grant — survives rebuilds.
set -euo pipefail

NAME="Nyx Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "'$NAME' identity already exists — nothing to do"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:FALSE
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/req.cnf"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/dev.p12" -passout pass:nyxdev -name "$NAME"

security import "$TMP/dev.p12" -k "$KEYCHAIN" -P nyxdev -T /usr/bin/codesign
echo "Marking the certificate trusted for code signing — this may ask for your login password."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Created '$NAME'. 'make app' will sign with it from now on."
echo "If codesign asks for keychain access on the next build, choose 'Always Allow'."
