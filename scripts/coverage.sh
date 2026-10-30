#!/bin/sh
# Line coverage of Sources/SNotateCore from the last
# `swift test --enable-code-coverage`. The shared code is covered by its own
# tests in ../scommon, which swift test here does not run.
set -eu
if ! xcrun swift --version >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
PROF=$(find .build -name default.profdata | head -1)
binary() {
    bundle=$(find .build -name "$1.xctest" -type d | head -1)
    if [ -f "$bundle/Contents/MacOS/$1" ]; then
        echo "$bundle/Contents/MacOS/$1"
    else
        echo "$bundle"
    fi
}
echo "SNotateCore only; scommon's coverage is its own (../scommon)"
xcrun llvm-cov report "$(binary SNotateCoreTests)" \
    -instr-profile "$PROF" -ignore-filename-regex='Tests/' Sources/SNotateCore
