#!/bin/sh
# README screenshots from the generated fixtures only (never real captures),
# through the app's snapshot hook, into docs/images/. Works on a copy of the
# sample case with the annotated sample sidecar and a scratch config.
set -eu
APP=build/sNotate.app/Contents/MacOS/sNotate
OUT=docs/images
WORK=build/screenshots
rm -rf "$WORK"
mkdir -p "$OUT" "$WORK"
cp -R fixtures/poc-sample-vm-migrate "$WORK/"
cp fixtures/sidecars/poc-sample-vm-migrate.snotate.json "$WORK/poc-sample-vm-migrate/"
shot() {
    name=$1
    keys=$2
    XDG_CONFIG_HOME="$PWD/$WORK/config" SNOTATE_WINDOW_SIZE=1200x760 SNOTATE_KEYS="$keys" \
        SNOTATE_SNAPSHOT="$PWD/$OUT/$name.png" "$APP" "$WORK/poc-sample-vm-migrate" >/dev/null 2>&1
    sips -Z 1200 "$OUT/$name.png" >/dev/null
    echo "screenshots: $OUT/$name.png"
}
shot canvas "wait@1500"
shot storyboard "cmd-2 wait@1500"
rm -rf "$WORK"
