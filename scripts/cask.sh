#!/bin/sh
# Fills the Homebrew cask from the release zip (SN-604). REPOSITORY is the
# GitHub owner/name the release is published under (default uSuite/snotate).
set -eu
VERSION=$(cat VERSION)
ZIP=build/release/sNotate-$VERSION.zip
REPOSITORY=${REPOSITORY:-uSuite/snotate}
[ -f "$ZIP" ] || { echo "cask: build $ZIP first with make release" >&2; exit 1; }
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
sed -e "s|@VERSION@|$VERSION|" -e "s|@SHA256@|$SHA|" -e "s|@REPOSITORY@|$REPOSITORY|g" \
    packaging/homebrew/snotate.rb.template > build/release/snotate.rb
echo "cask: build/release/snotate.rb for $REPOSITORY $VERSION"
