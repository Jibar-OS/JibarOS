# Building JibarOS

Target: Cuttlefish (`aosp_cf_x86_64_phone-trunk_staging-userdebug`). Non-Cuttlefish device trees are TODO — contributions welcome.

## Requirements

- Linux host (Ubuntu 22.04 LTS validated). 500 GB free disk. 64 GB RAM recommended.
- `repo` tool ([install instructions](https://source.android.com/docs/setup/download)).
- AOSP build prerequisites — see upstream [building requirements](https://source.android.com/docs/setup/start/requirements).
- Git LFS (for `oir-vendor-models`).

## Clone

```bash
mkdir jibar-os && cd jibar-os
curl -fsSL https://raw.githubusercontent.com/Jibar-OS/JibarOS/main/tools/bootstrap.sh | bash
```

`bootstrap.sh` does four things:
1. `repo init` against upstream AOSP at the JibarOS-pinned tag (`android-16.0.0_r3`).
2. Drops the JibarOS overlay manifest into `.repo/local_manifests/jibaros.xml`.
3. `repo sync -c -j8` (this is the long step — pulls AOSP + JibarOS overlays in one pass).
4. Runs the JibarOS bake step (applies 5 small patches to `frameworks/base/`, 3 device-tree patches to `device/google/cuttlefish/`, and copies the `oir-framework-addons` tree into place).

Every step is idempotent — re-run `bootstrap.sh` after an upstream bump and it reapplies cleanly.

If you'd rather run the steps by hand:

```bash
repo init -u https://android.googlesource.com/platform/manifest -b android-16.0.0_r3
mkdir -p .repo/local_manifests
curl -fsSL https://raw.githubusercontent.com/Jibar-OS/JibarOS/main/jibaros.xml \
    -o .repo/local_manifests/jibaros.xml
repo sync -c -j8
curl -fsSL https://raw.githubusercontent.com/Jibar-OS/JibarOS/main/tools/jibar-os-bake.sh | bash
```

## Build

```bash
source build/envsetup.sh
lunch aosp_cf_x86_64_phone-trunk_staging-userdebug
m -j$(nproc)
```

First build: 2–4 hours depending on hardware. Incremental rebuilds after editing OIR source are minutes.

## Run Cuttlefish

```bash
launch_cvd --start_webrtc=true --memory_mb=8192 --cpus=8
```

Point a browser at `https://localhost:8443/` and click `cvd-1`. Boot takes ~60 seconds.

## Validate

```bash
adb wait-for-device
adb shell cmd oir dumpsys capabilities
```

Expected on a clean Cuttlefish build (3 models + a voice WAV in `oir-vendor-models`):

```
OIR capabilities (12 total):
  text.complete         [RUNNABLE]
  text.translate        [RUNNABLE]
  text.embed            [RUNNABLE]
  audio.transcribe      [RUNNABLE]
  text.classify         [NO_DEFAULT_MODEL]
  text.rerank           [MODEL_MISSING]
  audio.synthesize      [MODEL_MISSING]
  audio.vad             [MODEL_MISSING]
  vision.embed          [MODEL_MISSING]   ← OEM opts in via PRODUCT_PACKAGES += oir_siglip_model
  vision.describe       [NO_DEFAULT_MODEL]
  vision.detect         [MODEL_MISSING]   ← OEM supplies an RT-DETR or YOLO ONNX
  vision.ocr            [NO_DEFAULT_MODEL]

Summary: 4 runnable, 3 unbacked, 5 model-missing
```

Launch **OirDemo** from the app drawer → tap **Fire All**. The 4 RUNNABLE tiles (`text.complete`, `text.translate`, `text.embed`, `audio.transcribe`) stream to completion; the 5th (`vision.detect`) shows a clean MODEL_MISSING error until an OEM bakes the detector.

## Incremental development

If you're iterating on a single OIR repo:

```bash
# Edit oird.cpp
m -j8 oird                                   # rebuild just oird
adb root && adb remount
adb push out/target/product/vsoc_x86_64/system_ext/bin/oird /system_ext/bin/oird
adb shell pkill oird                         # init respawns under new binary

# Same pattern for services.jar after editing OIRService.java:
m -j8 services
adb push out/target/product/vsoc_x86_64/system/framework/services.jar /system/framework/services.jar
adb push out/target/product/vsoc_x86_64/system/framework/oat/x86_64/services.{odex,vdex,art} /system/framework/oat/x86_64/
adb shell pkill system_server
```


## Troubleshooting

### `build completed successfully` but `launch_cvd` fails on `super.img` not found

AOSP's build produces component images (`system.img`, `system_ext.img`, etc.) but not `super.img` unless you run `m superimage`. If your workflow uses `lpmake` to repack super, the `BoardConfig.mk` for cuttlefish has the partition layout you'll need.

### `cmd oir dumpsys capabilities` reports everything `[MODEL_MISSING]`

Check `/product/etc/oir/` is populated:

```bash
adb shell ls /product/etc/oir/
```

If empty, the `oir-vendor-models` Git LFS pull may have failed during `repo sync`. Re-run:

```bash
cd vendor/oir-models && git lfs pull
```

### SELinux AVC denials in logcat for OIR

```bash
adb shell logcat | grep -i avc.*oir
```

If you see denials, it usually means device-tree sepolicy patches weren't applied — re-run `bootstrap.sh` (which is idempotent) or just the bake step:

```bash
curl -fsSL https://raw.githubusercontent.com/Jibar-OS/JibarOS/main/tools/jibar-os-bake.sh | bash
```

## See also

- [`CAPABILITIES.md`](./CAPABILITIES.md) — what's registered
- [`MODELS.md`](./MODELS.md) — model install paths + OEM bake-in
- [`KNOBS.md`](./KNOBS.md) — runtime tuning
