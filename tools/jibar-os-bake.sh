#!/bin/bash
# JibarOS post-sync bake step — applies oir-patches + copies
# oir-framework-addons into the AOSP tree. Idempotent.
#
# Run from the AOSP tree root after `repo sync`:
#   ./.repo/manifests/tools/jibar-os-bake.sh
#
# Or directly: tools/jibar-os-bake.sh (when running from manifest/).

set -euo pipefail

AOSP_ROOT="${AOSP_ROOT:-$PWD}"
ADDONS="$AOSP_ROOT/vendor/jibar-os/oir-framework-addons"
PATCHES="$AOSP_ROOT/vendor/jibar-os/oir-patches"
CVD="$AOSP_ROOT/vendor/jibar-os/device_google_cuttlefish"

if [ ! -d "$AOSP_ROOT/frameworks/base" ]; then
    echo "ERROR: not at AOSP root. cd to the tree first." >&2
    exit 1
fi
if [ ! -d "$ADDONS" ] || [ ! -d "$PATCHES" ] || [ ! -d "$CVD" ]; then
    echo "ERROR: JibarOS overlay repos not synced. Run repo sync." >&2
    exit 1
fi

echo "[jibar-os-bake] copy oir-framework-addons → frameworks/base/"
# rsync preserves existing files we don't touch; -a copies recursively.
# The addon tree mirrors frameworks/base/ layout exactly.
rsync -a "$ADDONS/frameworks/" "$AOSP_ROOT/frameworks/"

echo "[jibar-os-bake] apply oir-patches to frameworks/base/"
cd "$AOSP_ROOT/frameworks/base"
for p in "$PATCHES"/patches/*.patch; do
    [ -f "$p" ] || continue
    # git apply --check first — skip if already applied (idempotent).
    if git apply --reverse --check "$p" 2>/dev/null; then
        echo "  [already applied] $(basename "$p")"
    else
        git apply "$p"
        echo "  [applied] $(basename "$p")"
    fi
done

echo "[jibar-os-bake] apply device-tree patches + sepolicy to device/google/cuttlefish/"
cd "$AOSP_ROOT/device/google/cuttlefish"
for p in "$CVD"/*.patch; do
    [ -f "$p" ] || continue
    if git apply --reverse --check "$p" 2>/dev/null; then
        echo "  [already applied] $(basename "$p")"
    else
        git apply "$p"
        echo "  [applied] $(basename "$p")"
    fi
done
rsync -a "$CVD/shared/" "$AOSP_ROOT/device/google/cuttlefish/shared/"

echo "[jibar-os-bake] done. Tree ready for m/lunch."
