#!/bin/bash
# Fetches the App Store Connect API private key (.p8) from Doppler and
# writes it to fastlane/AuthKey_<KEY_ID>.p8. The .p8 is gitignored.
#
# Run this once after cloning or whenever the key rotates.
#
# Requires: doppler CLI logged in with access to the `going-the-distance` project.

set -euo pipefail

KEY_ID="CBN8V6XWA3"
OUT="$(dirname "$0")/AuthKey_${KEY_ID}.p8"

if [[ ! -s "$OUT" ]]; then
  doppler secrets get APP_STORE_CONNECT_API_KEY \
    --project going-the-distance --config dev --plain > "$OUT"
  chmod 600 "$OUT"
  echo "wrote $OUT"
else
  echo "$OUT already exists — skipping"
fi
