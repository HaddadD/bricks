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

asc certificates create --certificate-type DISTRIBUTION --generate-csr \
  --key-out dist.key --csr-out dist.csr --common-name "Wilson Lam" --email mail@wilsonlam.ca \
  --output json > dist.json

python3 -I -c '
import base64, json, sys
d = json.load(open("dist.json"))["data"]
open("dist.cer", "wb").write(base64.b64decode(d["attributes"]["certificateContent"]))
print("Created certificate", d["id"], "expires", d["attributes"].get("expirationDate"))
'

# Package key + certificate, then import so codesign can use it without prompting.
openssl rand -base64 24 > p12.password
asc certificates export --certificate dist.cer --private-key dist.key --csr dist.csr \
  --password-file p12.password --p12-out dist.p12 >/dev/null
security import dist.p12 -k ~/Library/Keychains/login.keychain-db -P "$(cat p12.password)" \
  -T /usr/bin/codesign -T /usr/bin/xcodebuild
chmod 600 "$DIR"/*

security find-identity -v -p codesigning | grep "Apple Distribution"
