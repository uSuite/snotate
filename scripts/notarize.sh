#!/bin/sh
# Notarise and staple the release zip (SN-604). Needs a paid Apple Developer
# account: DEVELOPER_ID set to the "Developer ID Application: ..." identity
# in the keychain, and NOTARY_PROFILE naming credentials stored once with
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team>
# Runs make release signed with that identity, submits, waits and staples.
set -eu
if [ -z "${DEVELOPER_ID:-}" ] || [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "notarize: set DEVELOPER_ID and NOTARY_PROFILE (see the comment at the top of this script)" >&2
    exit 1
fi
if ! security find-identity -v -p codesigning | grep -qF "$DEVELOPER_ID"; then
    echo "notarize: no signing identity '$DEVELOPER_ID' in the keychain" >&2
    exit 1
fi
VERSION=$(cat VERSION)
OUT=build/release
DEVELOPER_ID="$DEVELOPER_ID" scripts/release.sh
codesign --verify --strict --deep "$OUT/sNotate.app"
xcrun notarytool submit "$OUT/sNotate-$VERSION.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$OUT/sNotate.app"
rm "$OUT/sNotate-$VERSION.zip"
ditto -c -k --keepParent "$OUT/sNotate.app" "$OUT/sNotate-$VERSION.zip"
spctl --assess --type execute --verbose "$OUT/sNotate.app"
shasum -a 256 "$OUT/sNotate-$VERSION.zip"
