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

repo init -u https://github.com/Jibar-OS/manifest -b main
repo sync -c -j8

# Apply JibarOS patches + overlay (one command, idempotent)
./.repo/manifests/tools/jibar-os-bake.sh
```

The bake step does three things:
1. Applies 5 small patches from `oir-patches` to upstream AOSP files (69 lines total).
2. Applies 3 device-tree patches from `device_google_cuttlefish` to the Cuttlefish shared sepolicy.
3. Symlinks the `oir-framework-addons` tree into `frameworks/base/`.

Each step is idempotent — re-running the script after an `upstream` bump reapplies cleanly.

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

Expected on a clean Cuttlefish build (5 baseline models in `oir-vendor-models`):

```
OIR capabilities (12 total):
  text.complete         [RUNNABLE]
  text.embed            [RUNNABLE]
  audio.transcribe      [RUNNABLE]
  vision.embed          [RUNNABLE]
  vision.detect         [RUNNABLE]
  …
```

Launch **OirDemo** from the app drawer → tap **Fire All** → every RUNNABLE tile streams to completion.

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

A utility script `tools/cvd-push.sh` in the `manifest` repo wraps this pattern.

## Troubleshooting

### `build completed successfully` but `launch_cvd` fails on `super.img` not found

AOSP's build produces component images (`system.img`, `system_ext.img`, etc.) but not `super.img` unless you run `m superimage`. If your workflow uses `lpmake` to repack super, a helper lives at `tools/repack-super.sh` in `manifest`.

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

If you see denials, it usually means device-tree sepolicy patches weren't applied — re-run `./.repo/manifests/tools/jibar-os-bake.sh`.

## See also

- [`CAPABILITIES.md`](./CAPABILITIES.md) — what's registered
- [`MODELS.md`](./MODELS.md) — model install paths + OEM bake-in
- [`KNOBS.md`](./KNOBS.md) — runtime tuning
