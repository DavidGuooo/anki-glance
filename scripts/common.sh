# Shared by the release scripts. Source it; do not run it.
#
# Both builds of a release come from the same commit and carry the same numbers:
#   version  the argument, e.g. 0.2.0 (CFBundleShortVersionString)
#   build    the commit count (CFBundleVersion), so it rises with every release without
#            hand-editing. Sparkle and the App Store both compare this number.
set -euo pipefail

version=${1:?usage: $0 <version>, e.g. $0 0.2.0}
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ -n $(git status --porcelain) ]]; then
    echo "Working tree is not clean; commit or stash first so the release matches a commit." >&2
    exit 1
fi

build=$(git rev-list --count HEAD)
out=build/release
mkdir -p "$out"

# archive <scheme>: writes $out/<scheme>.xcarchive
archive() {
    xcodegen generate
    xcodebuild archive \
        -project AnkiGlance.xcodeproj -scheme "$1" -configuration Release \
        -archivePath "$out/$1.xcarchive" -derivedDataPath "build/DerivedData-$1" \
        MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build"
}
