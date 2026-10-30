#!/bin/sh
# Scripted UI smoke test: draws an arrow on a copy of the sample case, moves
# it, undoes and redoes the move, saves a snapshot to build/smoke/ and checks
# the sidecar the app wrote. Needs build/sNotate.app (make app).
set -eu

OUT=build/smoke
CASE=$OUT/poc-sample-vm-migrate
rm -rf "$CASE" "$OUT/config"
mkdir -p "$OUT"
# Every part reads its own config folder, never the user's keymap.
XDG_CONFIG_HOME="$PWD/$OUT/config"
export XDG_CONFIG_HOME
cp -R fixtures/poc-sample-vm-migrate "$OUT/"

# Arrow from (1000, 600) to (770, 720); grab it a quarter of the way along
# (the middle is its bend handle) and move it up 130, clear of any snap
# target at this window size; undo, redo.
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="a drag@1000,600:770,720 v drag@942,630:942,500 cmd-z cmd-Z" \
SNOTATE_SNAPSHOT="$OUT/arrow.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE" >/dev/null 2>&1

/usr/bin/python3 - "$CASE/poc-sample-vm-migrate.snotate.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    sidecar = json.load(f)
items = sidecar["steps"][0]["items"]
assert len(items) == 1, items
arrow = items[0]
assert arrow["type"] == "arrow", arrow
assert arrow["from"] == [1000, 470] and arrow["to"] == [770, 590], arrow
assert all(not step["items"] for step in sidecar["steps"][1:])
print("smoke: arrow drawn, moved, undone and redone; sidecar ok")
PY
test -s "$OUT/arrow.png"
echo "smoke: snapshot $OUT/arrow.png"

# Shapes, on the same case: an outline rectangle around the first button, r
# again for a filled one around the third, a shift circle; then select the
# first rectangle by its edge and option-drag its corner (resize about the
# centre), select the circle by its edge and fill it with f; [ finds no
# case before this one and cmd-[ sends the circle one step backward.
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="r drag@380,714:624,802 r drag@900,714:1144,802 e shift-drag@1300,300:1400,330 v click@380,758 alt-drag@624,802:644,830 click@1300,350 f [ cmd-[" \
SNOTATE_SNAPSHOT="$OUT/shapes.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE" >/dev/null 2>&1

/usr/bin/python3 - "$CASE/poc-sample-vm-migrate.snotate.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    items = json.load(f)["steps"][0]["items"]
shapes = [(i["type"], i["rect"], i.get("fill", False)) for i in items[1:]]
expected = [
    ("rectangle", [360, 686, 284, 144], False),
    ("ellipse", [1300, 300, 100, 100], True),
    ("rectangle", [900, 714, 244, 88], True),
]
assert items[0]["type"] == "arrow", items[0]
assert shapes == expected, shapes
print("smoke: rectangles, fill variant, circle, centre resize, fill and cmd-[ ok")
PY
test -s "$OUT/shapes.png"
echo "smoke: snapshot $OUT/shapes.png"

# Counters, on the empty steps 02 and 03: two on 02, one on 03 that
# continues at 3, then N restarts 03 at 1 (snapshot of 03 with the toast);
# a second run opens step 02 by its file and shows 1 and 2.
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="j j n click@392,726 click@652,726 j click@912,726 N" \
SNOTATE_SNAPSHOT="$OUT/counters-restart.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE" >/dev/null 2>&1
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_SNAPSHOT="$OUT/counters.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE/poc-sample-vm-migrate-02.png" >/dev/null 2>&1

/usr/bin/python3 - "$CASE/poc-sample-vm-migrate.snotate.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    steps = json.load(f)["steps"]
two, three = steps[2], steps[3]
assert [i["at"] for i in two["items"] if i["type"] == "counter"] == [[392, 726], [652, 726]], two
assert [i["at"] for i in three["items"] if i["type"] == "counter"] == [[912, 726]], three
assert three.get("restart_counter") is True and "restart_counter" not in two, three
print("smoke: counters placed across steps, step 03 restarted")
PY
test -s "$OUT/counters.png" && test -s "$OUT/counters-restart.png"
echo "smoke: snapshots $OUT/counters.png $OUT/counters-restart.png"

# Text, on step 04: click and type, enter; t again for the pill, drag a
# leader from the middle button and type, enter; select the first text and
# edit it with enter; double-click the second and edit it.
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="j j j j t click@400,450 type@Bấm_Migrate enter t drag@762,726:1000,560 type@Press_Migrate enter v click@405,460 enter type@_now enter dclick@1010,575 type@! enter" \
SNOTATE_SNAPSHOT="$OUT/text.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE" >/dev/null 2>&1

/usr/bin/python3 - "$CASE/poc-sample-vm-migrate.snotate.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    items = json.load(f)["steps"][4]["items"]
texts = [(i["text"], i["at"], i.get("pill", False), i.get("leader")) for i in items if i["type"] == "text"]
expected = [
    ("Bấm Migrate now", [400, 450], False, None),
    ("Press Migrate!", [1000, 560], True, [762, 726]),
]
assert texts == expected, texts
print("smoke: text typed, pill and leader, edited by enter and double-click")
PY
test -s "$OUT/text.png"
echo "smoke: snapshot $OUT/text.png"

# Highlights, on step 05: a marker over the title, then h again for two
# spotlights around the first and third buttons (snapshot of the shared
# dimming); a second run selects the second spotlight and turns it into a
# marker with f.
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="G h drag@384,386:700,438 h drag@380,714:624,802 drag@900,714:1144,802" \
SNOTATE_SNAPSHOT="$OUT/highlight-spotlights.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE" >/dev/null 2>&1
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="G v click@1000,750 f" \
SNOTATE_SNAPSHOT="$OUT/highlight.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE" >/dev/null 2>&1

/usr/bin/python3 - "$CASE/poc-sample-vm-migrate.snotate.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    items = json.load(f)["steps"][5]["items"]
marks = [(i["rect"], i.get("spotlight", False)) for i in items if i["type"] == "highlight"]
expected = [
    ([384, 386, 316, 52], False),
    ([380, 714, 244, 88], True),
    ([900, 714, 244, 88], False),
]
assert marks == expected, marks
print("smoke: marker, two spotlights, one switched back with f")
PY
test -s "$OUT/highlight.png" && test -s "$OUT/highlight-spotlights.png"
echo "smoke: snapshots $OUT/highlight-spotlights.png $OUT/highlight.png"

# Blur, on step 01: blur the IP in the title bar, b again to pixelate the
# large title (unreadable in the snapshot), then select the blur and turn it
# into pixelate with f.
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="j b drag@300,12:450,52 b drag@380,230:920,360 v click@375,30 f" \
SNOTATE_SNAPSHOT="$OUT/blur.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE" >/dev/null 2>&1

/usr/bin/python3 - "$CASE/poc-sample-vm-migrate.snotate.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    items = json.load(f)["steps"][1]["items"]
regions = [(i["rect"], i.get("pixelate", False)) for i in items if i["type"] == "blur"]
expected = [([300, 12, 150, 40], True), ([380, 230, 540, 130], True)]
assert regions == expected, regions
print("smoke: blur and pixelate regions, blur switched with f")
PY
test -s "$OUT/blur.png"
echo "smoke: snapshot $OUT/blur.png"

# Crop, on steps 01 to 03: crop 01 to the card, C on 02 and shrink it from
# its bottom-right handle, C on 03 and backspace removes it again; back on
# 02 with the crop tool (snapshot), then step 02 opened with the select tool
# shows the light dimming.
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="j c drag@320,140:1540,880 j C drag@1540,880:1500,860 j C backspace k" \
SNOTATE_SNAPSHOT="$OUT/crop.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE" >/dev/null 2>&1
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_SNAPSHOT="$OUT/crop-preview.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE/poc-sample-vm-migrate-02.png" >/dev/null 2>&1

/usr/bin/python3 - "$CASE/poc-sample-vm-migrate.snotate.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    steps = json.load(f)["steps"]
crops = [steps[n].get("crop") for n in (1, 2, 3)]
assert crops == [[320, 140, 1220, 740], [320, 140, 1180, 720], None], crops
print("smoke: crop drawn, copied with C and resized, removed with backspace")
PY
test -s "$OUT/crop.png" && test -s "$OUT/crop-preview.png"
echo "smoke: snapshots $OUT/crop.png $OUT/crop-preview.png"

# Zoom and pan, on step 05, with drags in view points so the expected
# stored pixels check the mapping: + + zooms to 1.5625 device pixels per
# image pixel (0.78125 points) about the centre and an arrow is drawn; with
# nothing selected, right and down pan to the image's edge and a second
# arrow is drawn; space-drag pans back by (100, 40) points and a third is
# drawn; z zooms to a 550 x 180 area (2 points per pixel) for a fourth;
# a fifth is undone with cmd-z through the Edit menu.
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="G + + a view-drag@100,100:300,200 esc esc right down a view-drag@100,160:300,300 space-view-drag@500,300:600,340 view-drag@100,250:300,310 z drag@200,150:750,330 view-drag@100,100:320,200 a view-drag@600,500:800,600 cmd-z" \
SNOTATE_SNAPSHOT="$OUT/zoom.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CASE" >/dev/null 2>&1

/usr/bin/python3 - "$CASE/poc-sample-vm-migrate.snotate.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    items = json.load(f)["steps"][5]["items"]
arrows = [(i["from"], i["to"]) for i in items if i["type"] == "arrow"]
expected = [
    ([224, 167.04], [480, 295.04]),
    ([320, 283.52], [576, 462.72]),
    ([192, 347.52], [448, 424.32]),
    ([250, 110], [360, 160]),
]
assert arrows == expected, arrows
print("smoke: zoom keys, arrow-key pan, space-drag pan and zoom to area map view to pixels")
PY
test -s "$OUT/zoom.png"
echo "smoke: snapshot $OUT/zoom.png"

# Cases, in a folder holding both sample cases and a folder of PNGs that
# is not a case: ] opens poc-sample-vm-scale in the same window and an
# arrow is drawn on its first step; ] again finds no later case; [ comes
# back with the arrow tool kept, :5 goes to step 5 (file 04) and a drag
# draws an arrow there.
NAV=$OUT/nav
rm -rf "$NAV"
mkdir -p "$NAV"
cp -R fixtures/poc-sample-vm-migrate fixtures/poc-sample-vm-scale fixtures/golden "$NAV/"
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="] a drag@200,200:500,300 ] [ : type@5 enter drag@300,300:600,400" \
SNOTATE_SNAPSHOT="$OUT/nav.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$NAV/poc-sample-vm-migrate" >/dev/null 2>&1

/usr/bin/python3 - "$NAV" <<'PY2'
import json, os, sys
nav = sys.argv[1]
def arrows(case, file):
    with open(os.path.join(nav, case, case + ".snotate.json")) as f:
        steps = json.load(f)["steps"]
    step = [s for s in steps if s["file"] == file][0]
    return [(i["from"], i["to"]) for i in step["items"] if i["type"] == "arrow"]
scale = arrows("poc-sample-vm-scale", "poc-sample-vm-scale-00.png")
assert scale == [([200, 200], [500, 300])], scale
migrate = arrows("poc-sample-vm-migrate", "poc-sample-vm-migrate-04.png")
assert migrate == [([300, 300], [600, 400])], migrate
assert not os.path.exists(os.path.join(nav, "golden", "golden.snotate.json"))
print("smoke: ] and [ move between cases keeping the tool, :5 goes to step 5")
PY2
test -s "$OUT/nav.png"
echo "smoke: snapshot $OUT/nav.png"

# Config: the first run wrote the default files into the smoke config
# folder. Then, with a config folder of its own: x is bound to the arrow
# tool and a is unbound, snapping is off and exports go to evidence/; a
# drag after a selects nothing, an arrow drawn with x keeps its unsnapped
# end, :set snap true rewrites one line, :export-config zips the folder,
# and a headless export writes into evidence/.
test -s "$OUT/config/snotate/config" && test -s "$OUT/config/snotate/keymap"
CUSTOM="$PWD/$OUT/custom"
CFG=$OUT/cfg
rm -rf "$CUSTOM" "$CFG" "$OUT/config.zip"
mkdir -p "$CUSTOM/snotate" "$CFG"
printf 'x tool arrow\na nop\n' > "$CUSTOM/snotate/keymap"
printf '# mine\nsnap false\nnotated_dir evidence\n' > "$CUSTOM/snotate/config"
cp -R fixtures/poc-sample-vm-migrate "$CFG/"
XDG_CONFIG_HOME="$CUSTOM" \
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="a drag@100,100:300,300 x drag@500,503:1597,498 : type@set_snap_true enter : type@export-config_$PWD/$OUT/config.zip enter" \
SNOTATE_SNAPSHOT="$OUT/config.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$CFG/poc-sample-vm-migrate" >/dev/null 2>&1
XDG_CONFIG_HOME="$CUSTOM" build/sNotate.app/Contents/MacOS/sNotate --export "$CFG/poc-sample-vm-migrate" >/dev/null

/usr/bin/python3 - "$CFG/poc-sample-vm-migrate" "$CUSTOM/snotate/config" "$OUT/config.zip" <<'PY2'
import json, os, sys, zipfile
case, config, archive = sys.argv[1:]
with open(os.path.join(case, "poc-sample-vm-migrate.snotate.json")) as f:
    items = json.load(f)["steps"][0]["items"]
arrows = [(i["from"], i["to"]) for i in items if i["type"] == "arrow"]
assert arrows == [([500, 503], [1597, 498])], items
assert open(config).read() == "# mine\nsnap true\nnotated_dir evidence\n", open(config).read()
assert sorted(zipfile.ZipFile(archive).namelist()) == ["snotate/", "snotate/config", "snotate/keymap", "snotate/styles"], zipfile.ZipFile(archive).namelist()
assert os.path.exists(os.path.join(case, "evidence", "poc-sample-vm-migrate-00.png"))
assert not os.path.exists(os.path.join(case, "notated"))
print("smoke: keymap rebinds and unbinds, snap off, :set, :export-config, notated_dir")
PY2
test -s "$OUT/config.png"
echo "smoke: snapshot $OUT/config.png"

# Styles, with a config folder of their own: preset 1 is recoloured and a
# preset 4 added. 4 draws an arrow in preset 4; 7, which the file lacks,
# is refused, so the next arrow is preset 4 too; with nothing selected, 1
# draws a third in preset 1. A
# headless export then shows each preset's colour in the pixels.
STY="$PWD/$OUT/styled"
SCASE=$OUT/sty
rm -rf "$STY" "$SCASE"
mkdir -p "$STY/snotate" "$SCASE"
printf 'preset 1\ncolor #2E7D32\n\npreset 4\ncolor #6A1B9A\n' > "$STY/snotate/styles"
cp -R fixtures/poc-sample-vm-migrate "$SCASE/"
XDG_CONFIG_HOME="$STY" \
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="4 a drag@300,300:900,300 7 drag@300,420:900,420 esc esc 1 a drag@300,600:900,600" \
SNOTATE_SNAPSHOT="$OUT/styles.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$SCASE/poc-sample-vm-migrate" >/dev/null 2>&1
XDG_CONFIG_HOME="$STY" build/sNotate.app/Contents/MacOS/sNotate --export "$SCASE/poc-sample-vm-migrate" >/dev/null
sips -s format bmp "$SCASE/poc-sample-vm-migrate/notated/poc-sample-vm-migrate-00.png" --out "$SCASE/export-00.bmp" >/dev/null

/usr/bin/python3 - "$SCASE/poc-sample-vm-migrate" "$SCASE/export-00.bmp" <<'PY2'
import json, os, struct, sys
case, bmp = sys.argv[1:]
with open(os.path.join(case, "poc-sample-vm-migrate.snotate.json")) as f:
    items = json.load(f)["steps"][0]["items"]
assert [i["preset"] for i in items] == [4, 4, 1], items
data = open(bmp, "rb").read()
offset, = struct.unpack_from("<I", data, 10)
width, height = struct.unpack_from("<ii", data, 18)
bpp, = struct.unpack_from("<H", data, 28)
row = (width * bpp // 8 + 3) & ~3
def pixel(x, y):
    line = (abs(height) - 1 - y) if height > 0 else y
    b, g, r = data[offset + line * row + x * bpp // 8:][:3]
    return r, g, b
def near(a, b):
    return all(abs(p - q) <= 3 for p, q in zip(a, b))
assert near(pixel(600, 300), (0x6A, 0x1B, 0x9A)), pixel(600, 300)
assert near(pixel(600, 420), (0x6A, 0x1B, 0x9A)), pixel(600, 420)
assert near(pixel(600, 600), (0x2E, 0x7D, 0x32)), pixel(600, 600)
print("smoke: styles file presets drawn and exported, undefined preset refused")
PY2
test -s "$OUT/styles.png"
echo "smoke: snapshot $OUT/styles.png"

# Storyboard, on a fresh copy of the annotated case: cmd-2 shows the
# frames, j j selects step 02, i opens its caption, cmd-a and typing
# replace it, enter writes it; the memo must differ from the fixture by
# exactly that line. Enter then opens step 02, where an arrow is drawn,
# and esc three times (tool, selection, back) returns to the storyboard
# for the snapshot.
SBC=$OUT/sb
rm -rf "$SBC"
mkdir -p "$SBC"
cp -R fixtures/poc-sample-vm-migrate "$SBC/"
cp fixtures/sidecars/poc-sample-vm-migrate.snotate.json "$SBC/poc-sample-vm-migrate/"
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="cmd-2 j j i cmd-a type@Pick_host-02_in_cluster_A enter enter a drag@300,200:600,260 esc esc esc" \
SNOTATE_SNAPSHOT="$OUT/storyboard.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$SBC/poc-sample-vm-migrate" >/dev/null 2>&1
diff fixtures/poc-sample-vm-migrate/poc-sample-vm-migrate.md "$SBC/poc-sample-vm-migrate/poc-sample-vm-migrate.md" > "$SBC/memo.diff" || true
printf '11c11\n< - Choose the target host in the same cluster\n---\n> - Pick host-02 in cluster A\n' | cmp -s - "$SBC/memo.diff" || { echo "smoke: memo diff is not one line:"; cat "$SBC/memo.diff"; exit 1; }

/usr/bin/python3 - "$SBC/poc-sample-vm-migrate" <<'PY2'
import json, os, sys
case = sys.argv[1]
with open(os.path.join(case, "poc-sample-vm-migrate.snotate.json")) as f:
    steps = json.load(f)["steps"]
step = [s for s in steps if s["file"] == "poc-sample-vm-migrate-02.png"][0]
arrows = [(i["from"], i["to"]) for i in step["items"] if i["type"] == "arrow"]
assert arrows == [([300, 200], [600, 260])], step["items"]
print("smoke: storyboard caption edits one memo line, enter opens the step, esc returns")
PY2
test -s "$OUT/storyboard.png"
echo "smoke: snapshot $OUT/storyboard.png"

# A case without a memo keeps its captions in the sidecar.
NOM=$OUT/nomemo
rm -rf "$NOM"
mkdir -p "$NOM"
cp -R fixtures/poc-sample-vm-migrate "$NOM/"
rm "$NOM/poc-sample-vm-migrate/poc-sample-vm-migrate.md"
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="j i type@Open_the_Actions_menu enter" \
SNOTATE_SNAPSHOT="$OUT/nomemo.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$NOM/poc-sample-vm-migrate" >/dev/null 2>&1
/usr/bin/python3 - "$NOM/poc-sample-vm-migrate" <<'PY2'
import json, os, sys
case = sys.argv[1]
assert not os.path.exists(os.path.join(case, "poc-sample-vm-migrate.md"))
with open(os.path.join(case, "poc-sample-vm-migrate.snotate.json")) as f:
    steps = json.load(f)["steps"]
captions = {s["file"]: s.get("caption") for s in steps if s.get("caption")}
assert captions == {"poc-sample-vm-migrate-01.png": "Open the Actions menu"}, captions
print("smoke: without a memo the caption goes to the sidecar")
PY2

# The 500 ms target: a 30-step case opens into the storyboard, timed from
# cmd-2 to the first paint (thumbnails stream in after it).
# In a folder of its own, so it is never a sibling of the other parts' case.
BIG=$OUT/big/poc-sample-vm-big
rm -rf "$OUT/big"
mkdir -p "$BIG"
for n in $(seq 0 29); do
    cp "fixtures/poc-sample-vm-migrate/poc-sample-vm-migrate-0$((n % 6)).png" "$BIG/poc-sample-vm-big-$(printf %02d "$n").png"
done
TIMING=$(SNOTATE_TIMING=1 SNOTATE_WINDOW_SIZE=1100x720 SNOTATE_KEYS="cmd-2" SNOTATE_SNAPSHOT="$OUT/big.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$BIG" 2>&1 >/dev/null | grep "timing: storyboard")
MS=$(echo "$TIMING" | grep "first paint" | awk '{printf "%d", $(NF-1)}')
ALL=$(echo "$TIMING" | grep "visible frames" | awk '{printf "%d", $(NF-1)}')
test -n "$MS" && test "$MS" -lt 500 || { echo "smoke: storyboard first paint too slow: $TIMING"; exit 1; }
echo "smoke: 30-step storyboard first paint in $MS ms, visible frames in ${ALL:-?} ms"

# Step operations, on a fresh copy: blur the IP field on step 01 and stamp
# it onto every later step with >, twice (no doubling); crop step 01 and
# stamp the crop with > while cropping; exclude step 03 with x. A headless
# export then skips 03 and lists it.
OPS=$OUT/ops
rm -rf "$OPS"
mkdir -p "$OPS"
cp -R fixtures/poc-sample-vm-migrate "$OPS/"
SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="j b drag@300,12:450,52 v click@375,30 > > c drag@320,140:1540,880 > v j j x" \
SNOTATE_SNAPSHOT="$OUT/ops.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$OPS/poc-sample-vm-migrate" >/dev/null 2>&1
build/sNotate.app/Contents/MacOS/sNotate --export "$OPS/poc-sample-vm-migrate" > "$OPS/export.txt"

/usr/bin/python3 - "$OPS/poc-sample-vm-migrate" "$OPS/export.txt" <<'PY2'
import json, os, sys
case, report = sys.argv[1:]
with open(os.path.join(case, "poc-sample-vm-migrate.snotate.json")) as f:
    steps = {s["file"]: s for s in json.load(f)["steps"]}
def step(n):
    return steps["poc-sample-vm-migrate-%02d.png" % n]
blurs = [[i["rect"] for i in step(n).get("items", []) if i["type"] == "blur"] for n in range(6)]
assert blurs == [[]] + [[[300, 12, 150, 40]]] * 5, blurs
crops = [step(n).get("crop") for n in range(6)]
assert crops == [None] + [[320, 140, 1220, 740]] * 5, crops
assert [bool(step(n).get("excluded")) for n in range(6)] == [False, False, False, True, False, False]
lines = open(report).read().splitlines()
assert "  excluded poc-sample-vm-migrate-03.png" in lines, lines
assert not os.path.exists(os.path.join(case, "notated", "poc-sample-vm-migrate-03.png"))
assert os.path.exists(os.path.join(case, "notated", "poc-sample-vm-migrate-04.png"))
print("smoke: > stamps the blur and the crop onto later steps once, x excludes and export lists it")
PY2
test -s "$OUT/ops.png"
echo "smoke: snapshot $OUT/ops.png"

# Reorder and rename plan (SN-303), in a folder of its own: the case as
# captured (scap- names, no memo). A drag in the storyboard puts step 04
# first, J moves it one later, and :rename-plan, confirmed by the hook,
# numbers the captures in that order; the bytes show which file went where.
RO=$OUT/reorder/poc-sample-vm-migrate
rm -rf "$OUT/reorder"
mkdir -p "$RO"
for n in 0 1 2 3 4 5; do
    cp "fixtures/poc-sample-vm-migrate/poc-sample-vm-migrate-0$n.png" "$RO/scap-2026-10-22-15220$n.png"
done
SNOTATE_CONFIRM=1 SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="cmd-2 board-drag@528,394:14,124 J : type@rename-plan enter" \
SNOTATE_SNAPSHOT="$OUT/reorder.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$RO" >/dev/null 2>&1
# With a memo, numbered captures keep their numbers and a new one follows.
RM=$OUT/reorder/memo/poc-sample-vm-migrate
mkdir -p "$OUT/reorder/memo"
cp -R fixtures/poc-sample-vm-migrate "$OUT/reorder/memo/"
cp fixtures/poc-sample-vm-migrate/poc-sample-vm-migrate-01.png "$RM/scap-2026-10-22-170000.png"
SNOTATE_CONFIRM=1 SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="G J K K : type@rename-plan enter" SNOTATE_SNAPSHOT="$OUT/reorder-memo.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$RM" >/dev/null 2>&1

/usr/bin/python3 - "$RO" "$RM" <<'PY2'
import json, os, sys
ro, rm = sys.argv[1:]
fixture = "fixtures/poc-sample-vm-migrate/poc-sample-vm-migrate-%02d.png"
def same(path, n):
    return open(path, "rb").read() == open(fixture % n, "rb").read()
names = sorted(f for f in os.listdir(ro) if f.endswith(".png"))
assert names == ["poc-sample-vm-migrate-%02d.png" % n for n in range(6)], names
assert [n for i in range(6) for n in range(6) if same(os.path.join(ro, names[i]), n)] == [0, 4, 1, 2, 3, 5]
with open(os.path.join(ro, "poc-sample-vm-migrate.snotate.json")) as f:
    assert [s["file"] for s in json.load(f)["steps"]] == names
for n in range(6):
    assert same(os.path.join(rm, "poc-sample-vm-migrate-%02d.png" % n), n)
assert same(os.path.join(rm, "poc-sample-vm-migrate-06.png"), 1)
assert not os.path.exists(os.path.join(rm, "scap-2026-10-22-170000.png"))
print("smoke: drag and J reorder, the rename plan numbers captures in story order, numbered ones kept once a memo exists")
PY2
test -s "$OUT/reorder.png"
echo "smoke: snapshot $OUT/reorder.png"

# Insert (SN-304), in a folder of its own: a capture dropped before the
# first frame becomes the first step, and one pasted (through a private
# pasteboard, never the user's clipboard) lands after the selected frame.
INS=$OUT/insert/poc-sample-vm-migrate
rm -rf "$OUT/insert"
mkdir -p "$OUT/insert"
cp -R fixtures/poc-sample-vm-migrate "$OUT/insert/"
SNOTATE_PASTEBOARD=snotate-smoke SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="cmd-2 drop@$PWD/fixtures/poc-sample-vm-migrate/poc-sample-vm-migrate-03.png@14,124 j paste@$PWD/fixtures/poc-sample-vm-migrate/poc-sample-vm-migrate-05.png" \
SNOTATE_SNAPSHOT="$OUT/insert.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$INS" >/dev/null 2>&1

/usr/bin/python3 - "$INS" <<'PY2'
import json, os, sys
case = sys.argv[1]
fixture = "fixtures/poc-sample-vm-migrate/poc-sample-vm-migrate-%02d.png"
with open(os.path.join(case, "poc-sample-vm-migrate.snotate.json")) as f:
    files = [s["file"] for s in json.load(f)["steps"]]
assert len(files) == 8, files
assert files[0].startswith("snotate-") and files[2].startswith("snotate-"), files
assert files[1] == "poc-sample-vm-migrate-00.png" and files[3] == "poc-sample-vm-migrate-01.png", files
assert open(os.path.join(case, files[0]), "rb").read() == open(fixture % 3, "rb").read()
assert open(os.path.join(case, files[2]), "rb").read() == open(fixture % 5, "rb").read()
print("smoke: a dropped capture becomes the first step and a pasted one lands after the selected frame")
PY2
test -s "$OUT/insert.png"
echo "smoke: snapshot $OUT/insert.png"

# Remove a step (SN-309), in a folder of its own and with a trash of its
# own: dd on step 3 moves its capture there and takes its memo block out,
# cmd-z puts both back byte for byte.
RMV=$OUT/remove
rm -rf "$RMV"
mkdir -p "$RMV/trash"
cp -R fixtures/poc-sample-vm-migrate "$RMV/"
SNOTATE_TRASH="$PWD/$RMV/trash" SNOTATE_DEBUG=1 SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="j j d d wait@300 cmd-z" \
SNOTATE_SNAPSHOT="$RMV/remove.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$RMV/poc-sample-vm-migrate" 2>"$RMV/log" >/dev/null
grep -q "^toast Moved poc-sample-vm-migrate-02.png to the Trash; cmd-z puts it back$" "$RMV/log"
grep -q "^toast Put poc-sample-vm-migrate-02.png back$" "$RMV/log"
grep -q "step 3/5  poc-sample-vm-migrate-03.png" "$RMV/log"
grep -q "step 3/6  poc-sample-vm-migrate-02.png" "$RMV/log"
test -z "$(ls "$RMV/trash")"
cmp -s "$RMV/poc-sample-vm-migrate/poc-sample-vm-migrate-02.png" fixtures/poc-sample-vm-migrate/poc-sample-vm-migrate-02.png
cmp -s "$RMV/poc-sample-vm-migrate/poc-sample-vm-migrate.md" fixtures/poc-sample-vm-migrate/poc-sample-vm-migrate.md
echo "smoke: dd moves a step's capture to the trash and its memo block out, cmd-z puts them back"

# Export from the window (SN-401, SN-402), on the annotated case in a
# folder of its own: cmd-E exports only step 01; then cmd-e exports the
# case (step 05 is excluded) and its toast is the snapshot. The files are
# the headless export's bytes.
EXP=$OUT/export/poc-sample-vm-migrate
rm -rf "$OUT/export"
mkdir -p "$OUT/export"
cp -R fixtures/poc-sample-vm-migrate "$OUT/export/"
cp fixtures/sidecars/poc-sample-vm-migrate.snotate.json "$EXP/"
SNOTATE_WINDOW_SIZE=1100x720 SNOTATE_KEYS="j cmd-E wait@1500" SNOTATE_SNAPSHOT="$OUT/export-step.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$EXP" >/dev/null 2>&1
ls "$EXP/notated" > "$OUT/export/one.txt"
SNOTATE_WINDOW_SIZE=1100x720 SNOTATE_KEYS="cmd-e wait@3000" SNOTATE_SNAPSHOT="$OUT/export.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$EXP" >/dev/null 2>&1
mkdir -p "$OUT/export/headless"
cp -R fixtures/poc-sample-vm-migrate "$OUT/export/headless/"
cp fixtures/sidecars/poc-sample-vm-migrate.snotate.json "$OUT/export/headless/poc-sample-vm-migrate/"
build/sNotate.app/Contents/MacOS/sNotate --export "$OUT/export/headless/poc-sample-vm-migrate" >/dev/null

/usr/bin/python3 - "$OUT/export" <<'PY2'
import os, sys
root = sys.argv[1]
assert open(os.path.join(root, "one.txt")).read().split() == ["poc-sample-vm-migrate-01.png"]
window = os.path.join(root, "poc-sample-vm-migrate", "notated")
headless = os.path.join(root, "headless", "poc-sample-vm-migrate", "notated")
names = sorted(os.listdir(window))
assert names == ["poc-sample-vm-migrate-%02d.png" % n for n in range(5)] + ["poc-sample-vm-migrate.md", "poc-sample-vm-migrate.yaml"], names
for name in names:
    assert open(os.path.join(window, name), "rb").read() == open(os.path.join(headless, name), "rb").read(), name
memo = open(os.path.join(window, "poc-sample-vm-migrate.md")).read()
assert "- Confirm the migration in the dialog\n\n![poc-sample-vm-migrate-03](poc-sample-vm-migrate-03.png)\n" in memo, memo
assert "poc-sample-vm-migrate-05" not in memo, memo
print("smoke: cmd-E exports one step, cmd-e the case and its labels, with the headless export's bytes")
PY2
test -s "$OUT/export.png"
echo "smoke: snapshot $OUT/export.png"

# Export options (SN-403), with a config of their own: a PNG export first,
# then cmd-e with jpeg at half size, captions burned in and counters left
# out; only the JPEGs remain, at half width and taller by the band.
OPT=$OUT/options/poc-sample-vm-migrate
OPTCFG="$PWD/$OUT/options-config"
rm -rf "$OUT/options" "$OPTCFG"
mkdir -p "$OUT/options" "$OPTCFG/snotate"
cp -R fixtures/poc-sample-vm-migrate "$OUT/options/"
cp fixtures/sidecars/poc-sample-vm-migrate.snotate.json "$OPT/"
build/sNotate.app/Contents/MacOS/sNotate --export "$OPT" >/dev/null
printf 'export_format jpeg\nexport_scale 0.5\nexport_captions true\nexport_counters false\n' > "$OPTCFG/snotate/config"
XDG_CONFIG_HOME="$OPTCFG" SNOTATE_WINDOW_SIZE=1100x720 SNOTATE_KEYS="cmd-e wait@3000" SNOTATE_SNAPSHOT="$OUT/options.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$OPT" >/dev/null 2>&1
ls "$OPT/notated" > "$OUT/options/names.txt"
sips -g pixelWidth -g pixelHeight "$OPT/notated/poc-sample-vm-migrate-01.jpg" > "$OUT/options/size.txt"
/usr/bin/python3 - "$OUT/options" <<'PY2'
import os, sys
root = sys.argv[1]
names = sorted(open(os.path.join(root, "names.txt")).read().split())
assert names == ["poc-sample-vm-migrate-%02d.jpg" % n for n in range(5)] + ["poc-sample-vm-migrate.md", "poc-sample-vm-migrate.yaml"], names
assert '    file: "poc-sample-vm-migrate-01.jpg"' in open(os.path.join(root, "poc-sample-vm-migrate", "notated", "poc-sample-vm-migrate.yaml")).read()
size = dict(line.split(": ") for line in open(os.path.join(root, "size.txt")).read().strip().splitlines()[1:])
assert int(size["  pixelWidth"]) == 800 and int(size["  pixelHeight"]) > 500, size
print("smoke: export options give half-size JPEGs with captions, and the PNGs are gone")
PY2

# Contact sheet and Typst fragment (SN-404), with a config of their own:
# a headless export writes the sheet as PNG and PDF and the fragment, a
# second writes nothing; when Typst is installed, a plain document
# including the fragment (which defines its own shot) must compile.
SHT=$OUT/sheet/poc-sample-vm-migrate
SHTCFG="$PWD/$OUT/sheet-config"
rm -rf "$OUT/sheet" "$SHTCFG"
mkdir -p "$OUT/sheet" "$SHTCFG/snotate"
cp -R fixtures/poc-sample-vm-migrate "$OUT/sheet/"
cp fixtures/sidecars/poc-sample-vm-migrate.snotate.json "$SHT/"
printf 'export_sheet both\nexport_typst true\n' > "$SHTCFG/snotate/config"
XDG_CONFIG_HOME="$SHTCFG" build/sNotate.app/Contents/MacOS/sNotate --export "$SHT" > "$OUT/sheet/first.txt"
XDG_CONFIG_HOME="$SHTCFG" build/sNotate.app/Contents/MacOS/sNotate --export "$SHT" > "$OUT/sheet/second.txt"
grep -q "wrote notated/poc-sample-vm-migrate-sheet.pdf" "$OUT/sheet/first.txt"
grep -q "wrote notated/poc-sample-vm-migrate.typ" "$OUT/sheet/first.txt"
grep -q "^  0 written" "$OUT/sheet/second.txt"
if command -v typst >/dev/null; then
    printf '= poc-sample-vm-migrate\n\n#include "notated/poc-sample-vm-migrate.typ"\n' > "$SHT/memo-check.typ"
    typst compile "$SHT/memo-check.typ" "$OUT/sheet/memo-check.pdf"
    echo "smoke: sheet and fragment exported once, and a memo including the fragment compiles"
else
    echo "smoke: sheet and fragment exported once (Typst missing, compile skipped)"
fi

# PoC root export (SN-405): a root holding the annotated case, the scale
# case without a sidecar and a nested product folder with another
# annotated case; make export exports both annotated cases, skips the
# other, and a second run writes nothing.
ROOTDIR=$OUT/root/poc-sample
rm -rf "$OUT/root"
mkdir -p "$ROOTDIR/nested"
cp -R fixtures/poc-sample-vm-migrate fixtures/poc-sample-vm-scale "$ROOTDIR/"
cp fixtures/sidecars/poc-sample-vm-migrate.snotate.json "$ROOTDIR/poc-sample-vm-migrate/"
cp -R "$ROOTDIR/poc-sample-vm-migrate" "$ROOTDIR/nested/"
make -s export ROOT="$ROOTDIR" > "$OUT/root/first.txt"
make -s export ROOT="$ROOTDIR" > "$OUT/root/second.txt"
tail -1 "$OUT/root/first.txt" | grep -q ": 2 cases exported, 1 without a sidecar skipped, 0 failed$"
test "$(grep -c '^  7 written' "$OUT/root/first.txt")" = 2
test "$(grep -c '^  0 written, 7 unchanged' "$OUT/root/second.txt")" = 2
test ! -e "$ROOTDIR/poc-sample-vm-scale/notated"
echo "smoke: make export walks a root, exports the annotated cases, skips the rest, and a second run writes nothing"


# Launcher and open events (SN-602): open -a with a capture, as Finder's
# Open With sends it, brings up that capture's step; the bundled launcher
# exports headless with --export and says so when it finds no app.
LCH=$OUT/launch
rm -rf "$LCH"
mkdir -p "$LCH"
cp -R fixtures/poc-sample-vm-migrate "$LCH/"
open -W -n -a "$PWD/build/sNotate.app" --env SNOTATE_DEBUG=1 --env SNOTATE_WINDOW_SIZE=1100x720 \
    --env "XDG_CONFIG_HOME=$PWD/$OUT/config" --env "SNOTATE_SNAPSHOT=$PWD/$LCH/open.png" \
    --stderr "$PWD/$LCH/open.log" "$LCH/poc-sample-vm-migrate/poc-sample-vm-migrate-03.png"
grep -q "^title poc-sample-vm-migrate  step 4/6  poc-sample-vm-migrate-03.png" "$LCH/open.log"
cp fixtures/sidecars/poc-sample-vm-migrate.snotate.json "$LCH/poc-sample-vm-migrate/"
build/sNotate.app/Contents/Resources/snotate --export "$LCH/poc-sample-vm-migrate" | grep -q "^  7 written"
! SNOTATE_APP=/nonexistent/sNotate.app scripts/snotate . 2>/dev/null
echo "smoke: open -a on a capture shows its step, and the bundled launcher exports headless"

# Settings window (SN-506), with a config folder of its own: each pane
# opens with its title, the preset pane draws its preview, and the styles
# file written on first run names the built-in presets.
SET=$OUT/settings
rm -rf "$SET"
mkdir -p "$SET/config"
for pane in general presets; do
    XDG_CONFIG_HOME="$PWD/$SET/config" SNOTATE_DEBUG=1 SNOTATE_SETTINGS=$pane SNOTATE_SNAPSHOT="$SET/$pane.png" \
        build/sNotate.app/Contents/MacOS/sNotate 2>"$SET/$pane.log" >/dev/null
    test -s "$SET/$pane.png"
done
grep -q "^settings General$" "$SET/general.log"
grep -q "^settings Presets$" "$SET/presets.log"
grep -q "^name Danger$" "$SET/config/snotate/styles"
echo "smoke: Settings opens on General and Presets, and the styles file names the presets"

# Menus and the ? overlay (SN-505, SN-503), with a keymap of their own that
# binds cmd-j to next, unbinds cmd-e and binds cmd-k to export: the menu
# shortcuts follow the keymap, cmd-j steps through the menu, cmd-e exports
# nothing, ? shows the overlay with the user's bindings, ? closes it and ?
# shows it again for the snapshot.
MNU=$OUT/menus
rm -rf "$MNU"
mkdir -p "$MNU/config/snotate"
cp -R fixtures/poc-sample-vm-migrate "$MNU/"
printf 'cmd-j next\ncmd-e nop\ncmd-k export\n' > "$MNU/config/snotate/keymap"
XDG_CONFIG_HOME="$PWD/$MNU/config" SNOTATE_DEBUG=1 SNOTATE_WINDOW_SIZE=1100x720 \
SNOTATE_KEYS="cmd-j cmd-j cmd-e wait@600 ? ? ?" \
SNOTATE_SNAPSHOT="$MNU/help.png" \
    build/sNotate.app/Contents/MacOS/sNotate "$MNU/poc-sample-vm-migrate" 2>"$MNU/log" >/dev/null
grep -q "^menu Next Step cmd-j$" "$MNU/log"
grep -q "^menu Export Case cmd-k$" "$MNU/log"
! grep -q " cmd-e$" "$MNU/log"
grep -q "step 3/6" "$MNU/log"
! grep -q "^toast Exported" "$MNU/log"
test ! -e "$MNU/poc-sample-vm-migrate/notated"
test "$(grep -c '^help shown' "$MNU/log")" = 2
grep -q "^help closed" "$MNU/log"
test -s "$MNU/help.png"
echo "smoke: menu shortcuts follow the keymap, and ? shows and hides the live keymap"
