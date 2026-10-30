#!/bin/sh
# Idle energy and leak check (SN-606), after sView's. Draws and edits on a
# copy of the sample case, opens the storyboard and comes back, lets the app
# settle, samples its CPU with top, then runs leaks on the live process with
# allocation stacks recorded. Fails when idle CPU is above 1% or when a
# leaked allocation was made from sNotate code; the fixed leaks of macOS
# frameworks at launch are reported but not counted.
set -u
APP=build/sNotate.app/Contents/MacOS/sNotate
OUT=build/idle
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R fixtures/poc-sample-vm-migrate "$OUT/"
MallocStackLogging=1 XDG_CONFIG_HOME="$PWD/$OUT/config" SNOTATE_WINDOW_SIZE=1100x720 \
    SNOTATE_KEYS="a drag@1000,600:770,720 r drag@380,714:624,802 j n click@392,726 cmd-z k cmd-2 cmd-1 + = b drag@100,100:400,160 G gg" \
    "$APP" "$OUT/poc-sample-vm-migrate" >/dev/null 2>&1 &
pid=$!
sleep 8
cpu=$(top -l 4 -s 2 -pid "$pid" -stats cpu | awk 'NR > 1 && /^[0-9.]+$/ {last = $1} END {print last + 0}')
leaks "$pid" >"$OUT/leaks.txt" 2>/dev/null
kill "$pid"
wait "$pid" 2>/dev/null
summary=$(grep -E '^Process .* leaks? for' "$OUT/leaks.txt" | head -1)
# Stack frames in our code, before the binary image list at the end.
ours=$(awk '/^Binary Images:/ {exit} {print}' "$OUT/leaks.txt" \
    | grep -E 'sNotate\.debug\.dylib|SNotateCore|SCommon|  sNotate ' | grep -cvE '^(Process|Path|Identifier):')
echo "idle: cpu ${cpu}% after settling"
echo "idle: ${summary:-leaks gave no summary}; ${ours} stack frames in sNotate code"
status=0
awk -v c="$cpu" 'BEGIN {exit !(c > 1.0)}' && status=1
[ "$ours" -eq 0 ] || status=1
exit $status
