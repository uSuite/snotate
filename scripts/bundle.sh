#!/bin/sh
# Wrap the SPM-built sNotate executable into build/sNotate.app with an ad-hoc
# signature. Used when Xcode or XcodeGen is not available.
set -eu

SWIFT=${SWIFT:-swift}
VERSION=${VERSION:-0.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
CONFIG=${CONFIG:-debug}
APP=build/sNotate.app

sh -c "$SWIFT build -c $CONFIG --product sNotate"
BIN_DIR=$(sh -c "$SWIFT build -c $CONFIG --show-bin-path")

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/sNotate" "$APP/Contents/MacOS/sNotate"
cp scripts/snotate "$APP/Contents/Resources/snotate"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed \
    -e "s/\$(EXECUTABLE_NAME)/sNotate/" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/io.github.usuite.snotate/" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null
echo "built $APP $VERSION ($BUILD_NUMBER)"
