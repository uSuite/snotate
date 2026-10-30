#!/bin/sh
# Hostile fixture pass in the UI (SN-605): the app must survive every case
# and say something sensible. Prints one line per case with the resident
# memory and the last title or toast; exits non-zero if the app died on any
# or a check failed. Works on copies in build/hostile-run, with a scratch
# config, so neither the fixtures nor the user's settings change. Ends with
# the activation check (make activate).
set -u
APP=build/sNotate.app/Contents/MacOS/sNotate
DATA=build/hostile
RUN=build/hostile-run
[ -d "$DATA/poc-hostile-many" ] || xcrun swift scripts/make-hostile.swift "$DATA" >/dev/null
rm -rf "$RUN"
mkdir -p "$RUN"
CONFIG=$PWD/$RUN/config
status=0

# run <label> <path> <keys> [action] [expect]: launch on a copy with the
# keys, run the action two seconds in, check the app is still alive five
# seconds in, and that its output contains expect when given.
run() {
    label=$1
    target=$2
    keys=$3
    action=${4:-}
    expect=${5:-}
    log=$RUN/$(echo "$label" | tr ' /' '--').log
    XDG_CONFIG_HOME="$CONFIG" SNOTATE_DEBUG=1 SNOTATE_WINDOW_SIZE=1100x720 SNOTATE_KEYS="$keys" \
        "$APP" "$target" >"$log" 2>&1 &
    pid=$!
    sleep 2
    if [ -n "$action" ]; then
        sh -c "$action"
    fi
    sleep 3
    if kill -0 "$pid" 2>/dev/null; then
        rss=$(ps -o rss= -p "$pid" | awk '{printf "%d", $1 / 1024}')
        kill "$pid"
        wait "$pid" 2>/dev/null
        said=$(grep -E '^(title|toast) ' "$log" | tail -1 | cut -c1-90)
        if [ -n "$expect" ] && ! grep -qF "$expect" "$log"; then
            printf 'hostile: SILENT %-22s %5s MB  expected "%s", last: %s\n' "$label" "$rss" "$expect" "$said"
            status=1
        else
            printf 'hostile: ok    %-22s %5s MB  %s\n' "$label" "$rss" "$said"
        fi
    else
        printf 'hostile: DIED  %-22s\n' "$label"
        tail -5 "$log"
        status=1
    fi
}

# copy <case>: a fresh copy of a hostile case under build/hostile-run.
copy() {
    rm -rf "${RUN:?}/$1"
    cp -R "$DATA/$1" "$RUN/"
    echo "$PWD/$RUN/$1"
}

run "8k capture" "$(copy poc-hostile-big)" "a drag@7000,1000:3000,4000 0 = cmd-2" "" "step 1/1"
run "100 steps" "$(copy poc-hostile-many)" "G gg cmd-2 G" "" "step 100/100"
run "unknown keys" "$(copy poc-hostile-unknown)" "n click@300,200" "" "step 1/1"
run "CRLF memo" "$(copy poc-hostile-crlf)" "cmd-2 j" "" "step 1/3"
run "BOM memo" "$(copy poc-hostile-bom)" "cmd-2 j" "" "step 1/3"
run "broken captures" "$(copy poc-hostile-broken)" "j j j cmd-2" "" "step 4/4"
run "deep colour" "$(copy poc-hostile-deep)" "G cmd-2" "" "step 5/5"
run "names" "$(copy poc-hostile-names)" "G cmd-2" "" "step 3/3"
run "conflict sidecar" "$(copy poc-hostile-conflict)" "n click@100,100" "" "Read-only"

case=$(copy poc-hostile-crlf)
run "capture renamed" "$case" "n click@100,100 wait@3000 j j" \
    "mv '$case/poc-hostile-crlf-01.png' '$case/renamed.png'" "poc-hostile-crlf-01.png is missing"
case=$(copy poc-hostile-crlf)
run "capture deleted" "$case" "n click@100,100 wait@3000 j" \
    "rm '$case/poc-hostile-crlf-01.png'" "poc-hostile-crlf-01.png is missing"
case=$(copy poc-hostile-unknown)
run "folder deleted" "$case" "wait@3000 n click@300,200" \
    "rm -rf '$case'" "The case folder is gone"
case=$(copy poc-hostile-unknown)
chmod a-w "$case"
run "read-only folder" "$case" "n click@300,200" "" "Not saved"
chmod u+w "$case"

# An external disk ejected while a case on it is open: a disk image detached
# with -force, then an edit.
IMAGE=$RUN/eject.dmg
hdiutil create -quiet -size 20m -fs APFS -volname snotate-eject "$IMAGE"
MOUNT=$(hdiutil attach -nobrowse "$IMAGE" 2>/dev/null | awk -F'\t' '/snotate-eject/ {print $NF}')
if [ -n "$MOUNT" ]; then
    cp -R "$DATA/poc-hostile-unknown" "$MOUNT/"
    run "disk ejected" "$MOUNT/poc-hostile-unknown" "wait@3000 n click@300,200" \
        "hdiutil detach -force '$MOUNT' >/dev/null 2>&1" "The case folder is gone"
    hdiutil detach -force "$MOUNT" >/dev/null 2>&1
else
    echo "hostile: SKIP  disk ejected (hdiutil attach failed)"
fi

scripts/activate.sh || status=1
exit $status
