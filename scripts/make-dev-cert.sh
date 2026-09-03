#!/bin/bash
# One-time: creates a self-signed "Nyx Dev" signing identity so the app's
# signature — and its Screen Recording grant — survives rebuilds.
# The certificate is NOT marked trusted: codesign accepts an untrusted leaf
# when it is addressed by hash, and TCC keys the grant to the leaf either way.
# Remove it with scripts/remove-dev-cert.sh.
set -euo pipefail

NAME="Nyx Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null \
  | grep -qE "^ *[0-9]+\) [0-9A-F]+ \"$NAME\"( \(.*\))?$"; then
  echo "'$NAME' identity already exists — nothing to do"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
P12PASS=$(/usr/bin/openssl rand -hex 24)

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
  -out "$TMP/dev.p12" -passout "pass:$P12PASS" -name "$NAME"

security import "$TMP/dev.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign

echo
echo "Created '$NAME' in your login keychain. 'make app' will sign with it from now on."
echo "Anything signed '$NAME' with identifier tech.unravel.nyx inherits Nyx's"
echo "Screen Recording grant — remove it with scripts/remove-dev-cert.sh when done."
echo "If codesign asks for keychain access on the next build, choose 'Always Allow'."
