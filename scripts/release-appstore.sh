#!/bin/bash
# Uploads the Mac App Store build to App Store Connect. Run it on the same commit as
# release-direct.sh so both builds carry the same version and build number.
#
#   scripts/release-appstore.sh 0.2.0
#
# Needs the app record created in App Store Connect. Uploads with an App Store Connect API key
# when scripts/release.env (not in git) sets ASC_KEY_ID and ASC_ISSUER_ID; the key file is
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 unless ASC_KEY_PATH says otherwise.
# Without them it falls back to the Apple ID signed in to Xcode.
# After the upload, submit the build for review in App Store Connect.
source "$(dirname "$0")/common.sh"

[[ -f scripts/release.env ]] && source scripts/release.env
auth=()
if [[ -n ${ASC_KEY_ID:-} && -n ${ASC_ISSUER_ID:-} ]]; then
    auth=(-authenticationKeyPath "${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}"
          -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

archive AnkiGlanceAppStore

rm -rf "$out/appstore"
xcodebuild -exportArchive \
    -archivePath "$out/AnkiGlanceAppStore.xcarchive" -exportPath "$out/appstore" \
    -exportOptionsPlist scripts/export-appstore.plist -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}

echo "Uploaded $version (build $build). Submit it for review in App Store Connect."
