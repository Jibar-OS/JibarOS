<p align="center">
  <img src="assets/banner.png" alt="JibarOS" width="100%"/>
</p>

<p align="center">
  <a href="https://www.loom.com/share/a4de8aa1666e4b9a8efa128f98b7f16c">
    <strong>▶ Watch the v0.6.9 concurrency demo (Loom, ~2 min)</strong>
  </a>
</p>

# JibarOS

**An Android-derivative OS with a built-in AI runtime at the platform layer.**

JibarOS is an AOSP fork that ships [Open Intelligence Runtime (OIR)](./docs/OVERVIEW.md) as a first-class system service — so any app on the device can call text, audio, and vision AI capabilities without bundling a model or a runtime.

Named after Puerto Rico's *jíbaros* — rural folk, known for resilience and self-sufficiency. Models and runtime live on the device, work offline, no cloud account required.

> ⚠️ **Current status:** pre-1.0. Validated on Android 16 Cuttlefish. No real-device ports yet.

## This repo

You're looking at the **main JibarOS repo** — the `repo init` target + the docs.

- [`default.xml`](./default.xml) — AOSP-style manifest pointing at every other JibarOS repo
- [`tools/jibar-os-bake.sh`](./tools/jibar-os-bake.sh) — post-sync bake: applies patches + wires overlays
- [`docs/`](./docs/) — architecture, capabilities, knobs, models, SDK, build guide

## Quick start

```bash
mkdir jibar-os && cd jibar-os
repo init -u https://github.com/Jibar-OS/jibar-os -b main
repo sync -c -j8
./.repo/manifests/tools/jibar-os-bake.sh
cd vendor/oir-models && ./tools/fetch-models.sh       # pull reference models
cd ../..
source build/envsetup.sh
lunch aosp_cf_x86_64_phone-trunk_staging-userdebug
m
launch_cvd --start_webrtc
```

See [`docs/BUILD.md`](./docs/BUILD.md) for the long version.

## The rest of the JibarOS org

The OS is split across purpose-focused repos — AOSP's `repo` tool wants one git repo per tree-path. See [`docs/OVERVIEW.md#repos`](./docs/OVERVIEW.md#repos) for the full list.

## License

Apache 2.0. See [`LICENSE`](./LICENSE) in each repo.
