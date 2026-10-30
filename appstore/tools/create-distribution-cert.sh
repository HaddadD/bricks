#!/bin/bash
# Creates an Apple Distribution certificate for team 76C669ZZ43 whose private key lives
# on this Mac, and installs it in the login keychain so Xcode can sign App Store builds.
# Needed once per Mac: certificates are tied to the private key that made them.
#
#   appstore/tools/create-distribution-cert.sh
#
# Everything is written to ~/.keys/signing (owner-only); the keychain gets the identity.
set -euo pipefail
DIR=~/.keys/signing
mkdir -p "$DIR" && chmod 700 "$DIR"
cd "$DIR"

umask 077

# Safe to rerun: a certificate created by an earlier run is reused, not duplicated.
if [ ! -s dist.json ]; then
  asc certificates create --certificate-type DISTRIBUTION --generate-csr \
    --key-out dist.key --csr-out dist.csr --common-name "Wilson Lam" --email mail@wilsonlam.ca \
    --output json > dist.json
fi

python3 -I -c '
import base64, json, sys
d = json.load(open("dist.json"))["data"]
open("dist.cer", "wb").write(base64.b64decode(d["attributes"]["certificateContent"]))
print("Certificate", d["id"], "expires", d["attributes"].get("expirationDate"))
'

# Import the key and certificate separately; the keychain pairs them into an identity.
# (A .p12 from OpenSSL 3+ uses SHA-256/AES-256, which `security import` can't read.)
# -T lets codesign and xcodebuild use the key without a keychain prompt.
# The keychain's "openssl" format is PKCS#1, and asc writes PKCS#8, so convert first.
KC=~/Library/Keychains/login.keychain-db
openssl rsa -in dist.key -traditional -out dist.rsa.key 2>/dev/null
security import dist.rsa.key -k "$KC" -t priv -f openssl -T /usr/bin/codesign -T /usr/bin/xcodebuild \
  || echo "(key already in keychain)"
security import dist.cer -k "$KC" || echo "(certificate already in keychain)"
chmod 600 "$DIR"/*

security find-identity -v -p codesigning | grep "Apple Distribution"
