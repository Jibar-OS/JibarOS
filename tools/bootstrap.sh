#!/bin/bash
# JibarOS bootstrap — one-command clean-clone setup.
#
# Layered on top of upstream AOSP via .repo/local_manifests/. Idempotent.
#
# Run from an empty directory (or a previously-bootstrapped JibarOS tree
# to re-sync after upstream / overlay updates):
#   curl -fsSL https://raw.githubusercontent.com/Jibar-OS/JibarOS/main/tools/bootstrap.sh | bash
#
# Or, if you already cloned JibarOS:
#   ./tools/bootstrap.sh

set -euo pipefail

AOSP_TAG="android-16.0.0_r3"
JIBAR_BRANCH="${JIBAR_BRANCH:-main}"
JIBAR_RAW="https://raw.githubusercontent.com/Jibar-OS/JibarOS/${JIBAR_BRANCH}"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: '$1' not in PATH. Install it first." >&2
        exit 1
    }
}
need repo
need git
need curl

echo "[bootstrap] step 1/4: repo init upstream AOSP @ ${AOSP_TAG}"
if [ ! -d .repo ]; then
    repo init -u https://android.googlesource.com/platform/manifest \
              -b "${AOSP_TAG}" --partial-clone --clone-filter=blob:limit=10M
fi

echo "[bootstrap] step 2/4: install JibarOS overlay manifest into local_manifests/"
mkdir -p .repo/local_manifests
curl -fsSL "${JIBAR_RAW}/jibaros.xml" -o .repo/local_manifests/jibaros.xml

echo "[bootstrap] step 3/4: repo sync (this is the long one)"
repo sync -c -j8

echo "[bootstrap] step 4/4: apply JibarOS bake (patches + framework overlay)"
curl -fsSL "${JIBAR_RAW}/tools/jibar-os-bake.sh" -o .repo/local_manifests/jibar-os-bake.sh
chmod +x .repo/local_manifests/jibar-os-bake.sh
.repo/local_manifests/jibar-os-bake.sh

cat <<EOF
[bootstrap] done. Next:

  source build/envsetup.sh
  lunch aosp_cf_x86_64_phone-trunk_staging-userdebug
  m -j\$(nproc)

See docs/BUILD.md for the full build + cuttlefish launch flow.
EOF
