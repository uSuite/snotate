#!/bin/sh
# Universal Release build and zip (SN-604). Signs with $DEVELOPER_ID and the
# hardened runtime when it is set ("Developer ID Application: ..."), ad hoc
# otherwise, which runs locally but cannot be notarised. Writes
# build/release/sNotate.app and build/release/sNotate-<version>.zip.
set -eu
VERSION=$(cat VERSION)
BUILD_NUMBER=$(git rev-list --count HEAD)
OUT=build/release

# A tag on HEAD must match VERSION, so a release never ships a stale number.
TAG=$(git tag --points-at HEAD | grep '^v' | head -1 || true)
if [ -n "$TAG" ] && [ "$TAG" != "v$VERSION" ]; then
    echo "release: HEAD is tagged $TAG but VERSION says $VERSION" >&2
    exit 1
fi

if [ -n "${DEVELOPER_ID:-}" ]; then
    SIGNING="CODE_SIGN_IDENTITY=$DEVELOPER_ID CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp"
else
    SIGNING="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual"
    echo "release: DEVELOPER_ID not set, signing ad hoc (local use only)"
fi

xcodegen generate >/dev/null
rm -rf "$OUT"
# shellcheck disable=SC2086
xcodebuild -project sNotate.xcodeproj -scheme sNotate -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath build/DerivedDataRelease \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    $SIGNING -quiet build
mkdir -p "$OUT"
cp -R build/DerivedDataRelease/Build/Products/Release/sNotate.app "$OUT/sNotate.app"
ditto -c -k --keepParent "$OUT/sNotate.app" "$OUT/sNotate-$VERSION.zip"
echo "release: $(lipo -archs "$OUT/sNotate.app/Contents/MacOS/sNotate") $VERSION ($BUILD_NUMBER)"
shasum -a 256 "$OUT/sNotate-$VERSION.zip"
