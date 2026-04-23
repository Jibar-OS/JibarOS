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

> ⭐ **Like what you see? Give this repo a star** — it's how GitHub decides whether to show the project to other people exploring on-device AI.

---

## How we got here — AAOSP → JibarOS

This project is the follow-up to [**AAOSP**](https://github.com/rufolangus/AAOSP), our earlier proof that a 0.5B-parameter LLM can run end-to-end inside AOSP on commodity hardware with real streaming inference. AAOSP answered the question *"can it run locally?"* — the answer was yes.

But AAOSP shipped as a bundled **chatbot app**. Every other app on the device would still need to bundle its own model, its own runtime, its own tokenizer — and pay the cost separately. That's not what on-device AI is supposed to be.

**JibarOS takes the insight from AAOSP and rewrites the shape.** Instead of "one AI app per device," inference becomes a platform layer — the OS loads models once and multiplexes them across every app that asks for a capability. The OS becomes the runtime. Apps declare what they need (`text.complete`, `vision.describe`, `audio.transcribe`, etc.) and the platform does the rest: residency, scheduling, concurrency, cancellation.

The capability-based API is mechanism, not policy. Agent orchestration, memory tiers, tool dispatch — those belong to layers above OIR.

> ⚠️ **Current status:** pre-1.0. Validated on Android 16 Cuttlefish. No real-device ports yet.

---

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
