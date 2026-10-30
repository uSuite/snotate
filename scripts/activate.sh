#!/bin/sh
# Activation after an exception (DECISIONS 2026-10-27). An Objective-C
# exception thrown inside a Swift task job was swallowed, left the main
# thread's executor bookkeeping dangling, and the next activation trapped in
# the main-actor check minutes later. The app now does AppKit work only in
# main-queue blocks, where an exception ends the app at once with its
# reason. Checks both: a scripted run survives three activations, and an
# exception raised through the test hook ends the app at once, by name.
set -u
APP=build/sNotate.app/Contents/MacOS/sNotate
OUT=build/activate
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R fixtures/poc-sample-vm-migrate "$OUT/"
front() {
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $1) to true" >/dev/null 2>&1
}
finder=$(pgrep -x Finder | head -1)

XDG_CONFIG_HOME="$PWD/$OUT/config" SNOTATE_KEYS="j a drag@1000,600:770,720 g" \
    "$APP" "$OUT/poc-sample-vm-migrate" >"$OUT/plain.log" 2>&1 &
pid=$!
sleep 3
for _ in 1 2 3; do
    front "$finder"
    sleep 0.5
    front "$pid"
    sleep 0.5
done
if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid"
    echo "activate: a scripted run died with status $? on activation" >&2
    exit 1
fi
kill "$pid"
echo "activate: a scripted run survives three activations"

XDG_CONFIG_HOME="$PWD/$OUT/config" SNOTATE_KEYS="raise@activate-check j" \
    "$APP" "$OUT/poc-sample-vm-migrate" >"$OUT/raise.log" 2>&1 &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
done
if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    echo "activate: an exception in the hook was swallowed" >&2
    exit 1
fi
if ! grep -q "reason: 'activate-check'" "$OUT/raise.log"; then
    echo "activate: the app died without naming the exception" >&2
    exit 1
fi
echo "activate: an exception ends the app at once, by name"
