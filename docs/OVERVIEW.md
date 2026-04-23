# JibarOS

**An Android-derivative OS with a built-in AI runtime at the platform layer.**

JibarOS is an AOSP fork that ships [Open Intelligence Runtime (OIR)](#open-intelligence-runtime-oir) as a first-class system service — so any app on the device can call text, audio, and vision AI capabilities without bundling a model or a runtime.

The name comes from the *jíbaros* — Puerto Rico's rural folk, known for resilience and self-sufficiency. The project inherits that spirit: models and runtime live on the device, work offline, and don't need a cloud account to function.

> ⚠️ **Current status:** pre-1.0. Validated end-to-end on Android 16 Cuttlefish. No real-device ports yet. Reference target is `aosp_cf_x86_64_phone`.

---

## Why this exists

Every new AI feature on Android today means an app bundles its own model, its own inference runtime, and its own tokenizer — often 300 MB+ of duplication per app. When three apps ship LLM assistants, the user pays the cost three times over.

JibarOS flips that. Models load once, at the platform layer, and are shared across every app that asks for a capability. An app calls `OpenIntelligence.text.completeStream("…")` and the runtime figures out the rest: which model, which context pool, priority relative to other in-flight requests, memory budget, cancellation.

The runtime is **mechanism, not policy**:

- The runtime does inference, residency, and scheduling.
- Agent orchestration, memory tiers, tool dispatch, and conversation state belong to layers **above** the runtime.

This is the same separation that made GPU drivers succeed: the driver doesn't decide what to render, it just renders fast and fairly. OIR doesn't decide what your AI app *does* — it makes the inference underneath fast and fair.

---

## Open Intelligence Runtime (OIR)

OIR is JibarOS's inference subsystem. It's architecturally separable from JibarOS — a different AOSP-based OS could integrate it — but JibarOS is the reference implementation.

### Capability surface

Apps speak to OIR through named capabilities. Each capability has a fixed *shape* (what the input and output look like) and a pluggable *backend model* (which GGUF / ONNX / other file serves requests).

| Capability | Shape | Reference backend |
|---|---|---|
| `text.complete` | TokenStream | Qwen 2.5 0.5B Instruct Q4_K_M (llama.cpp) |
| `text.translate` | TokenStream | shared with `text.complete` |
| `text.embed` | Vector | all-MiniLM-L6-v2 Q8_0 (llama.cpp) |
| `text.classify` | Vector | OEM-supplied ONNX classifier |
| `text.rerank` | Vector | OEM-supplied ONNX reranker |
| `audio.transcribe` | TokenStream | whisper-tiny.en Q5 (whisper.cpp) |
| `audio.synthesize` | AudioStream | OEM-supplied Piper voice + G2P sidecar |
| `audio.vad` | RealtimeBoolean | Silero VAD (ONNX Runtime) |
| `vision.embed` | Vector | SigLIP-base-patch16-224 (ONNX Runtime) |
| `vision.describe` | TokenStream | OEM-supplied VLM via libmtmd (LLaVA / SmolVLM / …) |
| `vision.detect` | BoundingBoxes | RT-DETR-R50vd-COCO (ONNX Runtime) |
| `vision.ocr` | BoundingBoxes | OEM-supplied det+rec ONNX pair |

An OEM building a JibarOS-based product bakes their chosen model per capability. Apps written against the capability surface don't have to change.

### What ships in the base image

A clean Cuttlefish build with `PRODUCT_PACKAGES += oird oir_default_model oir_minilm_model oir_whisper_tiny_en_model oir_voice_sample_wav oir_capabilities_xml` boots with 6 runnable capabilities out of the box:

- `text.complete`, `text.translate` (Qwen)
- `text.embed` (MiniLM)
- `audio.transcribe` (whisper-tiny)
- `vision.describe`, `vision.detect` (OEM-supplied)

All bundled models are permissively licensed (Apache 2.0 or MIT). Non-permissive models (LLaVA is research-only, YOLOv8 is AGPL) are explicitly marked as OEM-supplied so the base image stays redistributable.

### How it runs

```
┌───────────────────┐
│  App (any UID)    │   OpenIntelligence.text.completeStream("...")
└──────────┬────────┘
           │
           ▼  AIDL binder call
┌───────────────────┐
│  OIRService       │   Java platform service in system_server.
│  (system_server)  │   Enforces oir.permission.USE_TEXT / USE_AUDIO /
│                   │   USE_VISION; rate-limits per UID; dispatches to
└──────────┬────────┘   oird via IOirWorker AIDL.
           │
           ▼  AIDL binder call (in-device)
┌───────────────────┐
│  oird             │   Native daemon (C++). Owns model residency,
│  (system_ext/bin) │   ContextPool + WhisperPool with priority-aware
│                   │   wait queue, KV memory accounting, scheduler.
└──────────┬────────┘
           │
           ▼  shared-library call
┌───────────────────┐
│  llama.cpp /      │   Backend inference libraries.
│  whisper.cpp /    │   oird loads models on demand and shares them
│  ONNX Runtime /   │   across callers — the same loaded model serves
│  libmtmd          │   every app that asks for its capability.
└───────────────────┘
```

---

## How JibarOS differs from alternatives

| | JibarOS + OIR | Android NNAPI | LiteRT / MediaPipe |
|---|---|---|---|
| **Layer** | OS service | Tensor-level delegate | In-process library |
| **Who loads the model** | The OS (shared) | Each app (per-process) | Each app (per-process) |
| **Inter-app sharing** | Yes — one copy, N callers | No — one copy per app | No — one copy per app |
| **Unit of API** | Capability (`text.complete`, `vision.describe`, …) | Tensor graph | Task pipeline |
| **Model lifecycle** | Platform residency + budget + LRU | App-owned | App-owned |
| **Scheduling across apps** | Yes | No | No |

OIR sits at a higher level than NNAPI — it doesn't compete with it. Under the hood, OIR backends (llama.cpp, ONNX Runtime) could themselves use NNAPI delegates for hardware acceleration.

---

## Repos

JibarOS is a collection of repos under the [`jibar-os`](https://github.com/jibar-os) GitHub org. They split roughly into three groups:

### Core

| Repo | Contents |
|---|---|
| [`manifest`](https://github.com/jibar-os/manifest) | `.repo/manifests/` — the target for `repo init`. Points at every other repo in a reproducible set. |
| [`docs`](https://github.com/jibar-os/docs) | You are here. Landing page, architecture, OEM guide, roadmap. |
| [`oird`](https://github.com/jibar-os/oird) | Native inference daemon. C++ under `system/oird/`. |
| [`oir-framework-addons`](https://github.com/jibar-os/oir-framework-addons) | OIRService (Java), AIDL, capabilities.xml — everything new that lands under `frameworks/base/`. |
| [`oir-patches`](https://github.com/jibar-os/oir-patches) | Small patches to existing AOSP files (69 lines across 5 files). Applied at build-time. |
| [`oir-sdk`](https://github.com/jibar-os/oir-sdk) | Kotlin SDK (for apps) + AOSP companion (binder adapter). |
| [`oir-demo`](https://github.com/jibar-os/oir-demo) | OirDemo Mission Control app — concurrency showcase. Validates Fire All across every capability. |
| [`oir-vendor-models`](https://github.com/jibar-os/oir-vendor-models) | Permissively-licensed model bundle (~60 MB). Installed to `/product/etc/oir/`. |
| [`device_google_cuttlefish`](https://github.com/jibar-os/device_google_cuttlefish) | Reference device tree — AOSP Cuttlefish with OIR `PRODUCT_PACKAGES` + sepolicy. |

### External backends (forks we maintain)

| Repo | Upstream |
|---|---|
| [`platform_external_llamacpp`](https://github.com/jibar-os/platform_external_llamacpp) | [`ggml-org/llama.cpp`](https://github.com/ggml-org/llama.cpp) |
| [`platform_external_whispercpp`](https://github.com/jibar-os/platform_external_whispercpp) | [`ggml-org/whisper.cpp`](https://github.com/ggml-org/whisper.cpp) |
| [`platform_external_onnxruntime`](https://github.com/jibar-os/platform_external_onnxruntime) | [`microsoft/onnxruntime`](https://github.com/microsoft/onnxruntime) |
| [`platform_external_piper`](https://github.com/jibar-os/platform_external_piper) | [`rhasspy/piper`](https://github.com/rhasspy/piper) |

Forks exist so JibarOS can pin reproducible versions + carry any integration patches needed. Upstream bumps land on branches like `bump-bNNNN` per upstream cadence.

---

## Getting started

### For app developers

You want the SDK. See [`oir-sdk`](https://github.com/jibar-os/oir-sdk) — add as a dependency, call `OpenIntelligence.text.completeStream(...)`, done. Works on any JibarOS-based device.

### For OEMs considering a JibarOS-based product

Start with the [OEM bake-in guide](./OEM_BAKE_IN.md) (TODO — coming soon). The short version:

1. Clone a reference JibarOS build for your device class.
2. Pick your model per capability (`vision.describe` is where most OEMs differentiate).
3. Bake them into your `PRODUCT_PACKAGES` via `oir-vendor-models` or your own vendor repo.
4. Validate against the OIR reference test suite (TODO).

### For JibarOS contributors

```bash
# Once JibarOS is ready for external contributors:
mkdir jibar-os && cd jibar-os
repo init -u https://github.com/jibar-os/manifest -b main
repo sync -c -j8
source build/envsetup.sh
lunch aosp_cf_x86_64_phone-trunk_staging-userdebug
m
launch_cvd --start_webrtc
```

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the contribution flow.

---

## Roadmap

Tracked in [`ROADMAP.md`](./ROADMAP.md) (TODO — coming soon).

Next milestones:

- **v0.7** — public SDK surface stabilization; Vulkan acceleration for llama.cpp + VLM paths.
- **v0.8** — real-device port (first target TBD — contributions welcome).
- **v1.0** — stable capability surface; first external OEM onboarding.

---

## License

Apache 2.0. See [`LICENSE`](./LICENSE) in each repo.

All first-party code is Apache 2.0. Third-party backends retain their upstream licenses (llama.cpp is MIT, whisper.cpp is MIT, ONNX Runtime is MIT, Piper is MIT, libmtmd is MIT). Bundled model weights are each tagged with their permissive upstream license (see [`oir-vendor-models/NOTICE`](https://github.com/jibar-os/oir-vendor-models/blob/main/NOTICE)).
