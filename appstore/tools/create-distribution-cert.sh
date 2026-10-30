#!/bin/bash
# Creates a signing certificate for team 76C669ZZ43 whose private key lives on this Mac,
# and installs it in the login keychain so Xcode can sign App Store builds. Needed once
# per Mac: certificates are tied to the private key that made them.
#
#   appstore/tools/create-distribution-cert.sh             Apple Distribution (every platform's app)
#   appstore/tools/create-distribution-cert.sh installer   Mac Installer Distribution (the Mac .pkg)
#
# Everything is written to ~/.keys/signing (owner-only); the keychain gets the identity.
set -euo pipefail
DIR=~/.keys/signing
mkdir -p "$DIR" && chmod 700 "$DIR"
cd "$DIR"

umask 077

if [ "${1:-}" = installer ]; then
  TYPE=MAC_INSTALLER_DISTRIBUTION NAME=installer MATCH="Installer"
else
  TYPE=DISTRIBUTION NAME=dist MATCH="Apple Distribution"
fi

# Safe to rerun: a certificate created by an earlier run is reused, not duplicated.
if [ ! -s $NAME.json ]; then
  asc certificates create --certificate-type $TYPE --generate-csr \
    --key-out $NAME.key --csr-out $NAME.csr --common-name "Wilson Lam" --email mail@wilsonlam.ca \
    --output json > $NAME.json
fi

python3 -I -c '
import base64, json, sys
name = sys.argv[1]
d = json.load(open(name + ".json"))["data"]
open(name + ".cer", "wb").write(base64.b64decode(d["attributes"]["certificateContent"]))
print("Certificate", d["id"], "expires", d["attributes"].get("expirationDate"))
' $NAME

# Import the key and certificate separately; the keychain pairs them into an identity.
# (A .p12 from OpenSSL 3+ uses SHA-256/AES-256, which `security import` can't read.)
# -T lets codesign, productbuild and xcodebuild use the key without a keychain prompt.
# The keychain's "openssl" format is PKCS#1, and asc writes PKCS#8, so convert first.
KC=~/Library/Keychains/login.keychain-db
openssl rsa -in $NAME.key -traditional -out $NAME.rsa.key 2>/dev/null
security import $NAME.rsa.key -k "$KC" -t priv -f openssl \
  -T /usr/bin/codesign -T /usr/bin/productbuild -T /usr/bin/xcodebuild \
  || echo "(key already in keychain)"
security import $NAME.cer -k "$KC" || echo "(certificate already in keychain)"
chmod 600 "$DIR"/*

security find-identity -v | grep "$MATCH"
