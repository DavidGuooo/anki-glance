#!/bin/bash
# Publishes the direct-download build: Developer ID signed, notarized, attached to a GitHub
# release, and announced in the Sparkle feed (docs/appcast.xml, served by GitHub Pages).
#
#   scripts/release-direct.sh 0.2.0
#
# Needs, once per machine:
#   - a "Developer ID Application" certificate for the team
#   - notarization credentials:  xcrun notarytool store-credentials anki-glance-notary
#   - the Sparkle signing key in the login keychain (its public half is SUPublicEDKey in project.yml)
source "$(dirname "$0")/common.sh"

notary_profile=${NOTARY_PROFILE:-anki-glance-notary}
tag="v$version"
repo_url=https://github.com/DavidGuooo/anki-glance
sparkle_bin=build/DerivedData-AnkiGlance/SourcePackages/artifacts/sparkle/Sparkle/bin

archive AnkiGlance

rm -rf "$out/direct"
xcodebuild -exportArchive \
    -archivePath "$out/AnkiGlance.xcarchive" -exportPath "$out/direct" \
    -exportOptionsPlist scripts/export-direct.plist -allowProvisioningUpdates
app="$out/direct/Anki Glance.app"

# Notarize, then staple the ticket so the app opens without a network check.
ditto -c -k --keepParent "$app" "$out/notarize.zip"
xcrun notarytool submit "$out/notarize.zip" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app"

# The update archive must be zipped after stapling. generate_appcast signs it and adds an
# entry to the existing feed; entries for earlier releases are kept.
updates="$out/updates"
rm -rf "$updates" && mkdir -p "$updates"
ditto -c -k --keepParent "$app" "$updates/AnkiGlance-$version.zip"
[[ -f docs/appcast.xml ]] && cp docs/appcast.xml "$updates/"
"$sparkle_bin/generate_appcast" \
    --download-url-prefix "$repo_url/releases/download/$tag/" \
    --link "$repo_url" "$updates"

# Publish the download first, then the feed that points at it.
git tag "$tag"
git push origin "$tag"
gh release create "$tag" "$updates/AnkiGlance-$version.zip" --title "Anki Glance $version" --generate-notes
cp "$updates/appcast.xml" docs/appcast.xml
git add docs/appcast.xml
git commit -m "Release $version: update the Sparkle feed" -- docs/appcast.xml
git push origin HEAD

echo "Released $version (build $build). Installed copies will see it on their next update check."
