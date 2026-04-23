<p align="center">
  <img src="assets/banner.png" alt="JibarOS" width="100%"/>
</p>

<p align="center">
  <a href="https://github.com/Jibar-OS/jibar-os/stargazers">
    <img src="https://img.shields.io/github/stars/Jibar-OS/jibar-os?style=social" alt="Stars" />
  </a>
  <img src="https://img.shields.io/badge/Android-16-34A853?logo=android&logoColor=white" alt="Android 16" />
  <img src="https://img.shields.io/badge/License-Apache%202.0-blue" alt="Apache 2.0" />
  <img src="https://img.shields.io/badge/Status-pre--1.0-orange" alt="pre-1.0" />
</p>

<p align="center">
  <a href="https://www.loom.com/share/a4de8aa1666e4b9a8efa128f98b7f16c">
    <img src="https://cdn.loom.com/sessions/thumbnails/a4de8aa1666e4b9a8efa128f98b7f16c-7826565414152998-full-play.gif"
         alt="v0.6.9 Fire All demo — Loom"
         width="720"/>
  </a>
</p>

<p align="center">
  <em>v0.6.9 Fire All on Cuttlefish — 6 capabilities streaming concurrently through the OIR platform service.</em>
  <br/>
  <a href="https://www.loom.com/share/a4de8aa1666e4b9a8efa128f98b7f16c">▶ Watch the full ~2 min demo</a>
</p>

# JibarOS

**An Android 16 fork where AI is a platform primitive, not an app feature.**

Twelve AI capabilities — text completion, translation, embeddings, classification, rerank, transcription, synthesis, VAD, image embeddings, description, detection, OCR — exposed to every app on the device through a single binder AIDL. **One system service. One native daemon. Four pluggable backends. Pooled residency. Per-UID rate limits. Priority-aware scheduling. OEM-configurable per capability.** Models load once at the platform tier and are shared across every app that asks.

This is runtime infrastructure, not a chatbot. The closest mental model is **"a kernel for on-device inference"** — the OS owns the hardware (well, the model + the KV cache), schedules access, enforces permissions, accounts memory. Apps make system calls (well, binder calls) and get answers.

Named after Puerto Rico's *jíbaros* — rural folk, known for resilience and self-sufficiency. Models and runtime live on the device, work offline, no cloud account required.

> ⭐ **[Star this repo](https://github.com/Jibar-OS/jibar-os)** — it's the cheapest signal that on-device AI belongs at the platform tier, and it helps the right contributors find the project.

---

## Why this exists

Every new AI feature on Android today means an app bundles its own model, its own runtime, its own tokenizer — easily 300+ MB of duplication per app. When three apps ship LLM assistants, the user pays the cost three times over. When the device has 8 GB RAM, two resident LLMs already push the budget.

JibarOS flips that. **Load once, serve many.** An app calls `Oir.text.completeStream("…")` and the runtime figures out the rest — which model, which context pool, priority relative to other in-flight requests, memory budget, cancellation. Shipping this at the platform tier is the only way on-device AI scales past the first couple of apps.

OEMs pick the actual backing model per capability (small VLM for a thin phone, 7B LLM for a flagship). Apps targeting the capability surface don't change.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Apps (any UID)                                                 │
│  Oir.text.completeStream(...) / Oir.audio.transcribeStream(...)│
│           │ Oir.vision.describe(...) / Oir.vision.detect(...)  │
│           ▼                                                     │
├────────────────────────────────────────────────────────────────┤
│  OIRService (system_server)                                     │
│  ├─ enforces oir.permission.USE_TEXT / USE_AUDIO / USE_VISION   │
│  ├─ per-UID rate limiting (token bucket)                        │
│  ├─ capability registry (capabilities.xml + OEM fragments)      │
│  └─ dispatches to oird over IOirWorker AIDL                     │
├────────────────────────────────────────────────────────────────┤
│  oird (native daemon, /system_ext/bin/oird, u:r:oird:s0)        │
│  ├─ shared model residency — one load per capability            │
│  ├─ ContextPool / WhisperPool (priority-aware wait queues)      │
│  ├─ KV-cache memory accounting + LRU eviction                   │
│  └─ cross-backend scheduler with per-capability priority        │
├────────────────────────────────────────────────────────────────┤
│  Backends                                                        │
│  llama.cpp  │  whisper.cpp  │  ONNX Runtime  │  libmtmd         │
│  (GGUFs)    │  (.bin)       │  (.onnx)       │  (VLMs)         │
└────────────────────────────────────────────────────────────────┘
```

Three load-bearing ideas:

1. **Capability, not tensor.** Apps ask for `text.complete` or `vision.describe`. They never touch tensors, runtimes, or tokenizers. The platform owns the inference graph.
2. **One loaded model per capability, shared across every caller.** If three apps want `text.complete`, the GGUF loads once. KV cache is budgeted. Contexts are pooled. Concurrent inference interleaves at the pool-slot level.
3. **Mechanism, not policy.** The runtime does inference, residency, and scheduling. Agent orchestration, memory tiers, tool dispatch, conversation state — those are not in OIR. They sit above.

---

## Capabilities (v0.6.9)

| Capability | Shape | Reference backend | Permission |
|---|---|---|---|
| `text.complete` | TokenStream | Qwen 2.5 0.5B Q4_K_M (llama.cpp) | `USE_TEXT` |
| `text.translate` | TokenStream | shared with `text.complete` | `USE_TEXT` |
| `text.embed` | Vector | all-MiniLM-L6-v2 Q8_0 (llama.cpp) | `USE_TEXT` |
| `text.classify` | Vector | OEM-supplied ONNX classifier | `USE_TEXT` |
| `text.rerank` | Vector | OEM-supplied (ms-marco-MiniLM-style) | `USE_TEXT` |
| `audio.transcribe` | TokenStream | whisper-tiny.en Q5 (whisper.cpp) | `USE_AUDIO` |
| `audio.synthesize` | AudioStream | OEM-supplied Piper voice + G2P sidecar (ONNX Runtime) | `USE_AUDIO` |
| `audio.vad` | RealtimeBoolean | Silero VAD (ONNX Runtime) | `USE_AUDIO` |
| `vision.embed` | Vector | SigLIP-base-patch16-224 (ONNX Runtime) | `USE_VISION` |
| `vision.describe` | TokenStream | OEM-supplied VLM via libmtmd (LLaVA / SmolVLM / …) | `USE_VISION` |
| `vision.detect` | BoundingBoxes | RT-DETR-R50vd-COCO (ONNX Runtime) | `USE_VISION` |
| `vision.ocr` | BoundingBoxes | OEM-supplied det+rec pair (ONNX Runtime) | `USE_VISION` |

Full details: [`docs/CAPABILITIES.md`](./docs/CAPABILITIES.md).

---

## OEM-ready: pick the model per capability

JibarOS declares the capability contract; OEMs pick the backing model. Two mechanisms:

**Platform bake-in** — the reference Cuttlefish build ships 5 permissive defaults via [`oir-vendor-models`](https://github.com/Jibar-OS/oir-vendor-models) (Apache 2.0 + MIT). `PRODUCT_PACKAGES += oir_default_model oir_minilm_model oir_whisper_tiny_en_model …` installs them to `/product/etc/oir/` at build time.

**Per-OEM override** — drop `/vendor/etc/oir/oir_config.xml` on your image:

```xml
<oir_config>
  <capability_tuning>
    <capability name="vision.describe">
      <default_model>/product/etc/oir/mmproj.gguf|/product/etc/oir/llm.gguf</default_model>
    </capability>
  </capability_tuning>
</oir_config>
```

Swap LLaVA-1.5-7B for SmolVLM-500M on a thin device. No framework changes, no app changes. Full guide: [`docs/MODELS.md`](./docs/MODELS.md).

---

## Runtime + memory management

**Shared residency.** Every app calling `Oir.text.completeStream` hits the SAME loaded model. That model has a **context pool** with N slots (default 4 for `text.complete`); each slot is an independent `llama_context` with its own KV cache. Concurrent submits interleave at the slot level.

**Budget accounting.** Every loaded model reports weights + pool KV cache in its resident footprint. When a new load would exceed the configured memory budget, LRU eviction runs — skipping models that are in-flight or inside a `warm()` TTL window.

**Priority-aware queues.** `audio.*` capabilities default to `AUDIO_REALTIME`; everything else to `NORMAL`. Queued audio submits jump ahead of queued text submits within a shared pool. Priority is queue-order, not preemption — a long in-flight completion runs to completion.

**Concurrency proof.** v0.6.9 Fire All validated on Cuttlefish: five concurrent `load*()` calls across four backends (text.complete + text.embed + audio.transcribe + vision.detect + vision.describe) all resolved without hangs, six capabilities streamed simultaneously. See the Loom above.

---

## Tuning knobs

OEMs tune per-capability behavior via `/vendor/etc/oir/oir_config.xml`. Global knobs: memory budget, warm TTL, inference timeout, rate limits. Per-capability: context window, max tokens, contexts-per-model, acquire timeout, priority, temperature, top-p, preprocess sizes, detection thresholds.

Full reference: [`docs/KNOBS.md`](./docs/KNOBS.md).

---

## SDK

Apps consume OIR via the [`oir-sdk`](https://github.com/Jibar-OS/oir-sdk) Kotlin library. Structured concurrency, typed errors, Java interop.

```kotlin
import com.oir.Oir

Oir.text.completeStream("Summarize this in one sentence: …")
    .collect { chunk -> print(chunk.text) }

val vector: FloatArray = Oir.text.embed("vector me")

Oir.audio.transcribeStream("/sdcard/voice.wav")
    .collect { chunk -> println(chunk.text) }

val boxes = Oir.vision.detect("/sdcard/photo.jpg")
```

Full guide: [`docs/SDK.md`](./docs/SDK.md).

---

## AAOSP → JibarOS

Builds directly on [**AAOSP**](https://github.com/rufolangus/AAOSP) — the earlier Android 15 fork that first put an LLM inside `system_server` as a platform service (`LlmManagerService`) and introduced MCP tool-calling at the manifest layer.

AAOSP proved the core insight: **on-device AI belongs at the platform tier, not bundled per-app.** Any app with an `<mcp-server>` declaration becomes reachable by the platform LLM. HITL consent + audit is a platform invariant.

JibarOS extends that pattern to a **broader runtime surface** on Android 16. Where AAOSP's `LlmManagerService` is purpose-built for MCP tool-calling with one llama.cpp LLM, OIR is the general inference layer: 12 capabilities across text/audio/vision, four pluggable backends (llama.cpp / whisper.cpp / ONNX Runtime / libmtmd), pooled residency, KV budget, cross-backend priority scheduler. An AAOSP-style MCP agent, or any other agent framework, could sit on top of OIR and use it as the inference substrate — that's what "mechanism, not policy" means in practice.

Complementary, not competitive.

---

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

Full guide: [`docs/BUILD.md`](./docs/BUILD.md).

---

## Repos in this org

See [`docs/OVERVIEW.md#repos`](./docs/OVERVIEW.md#repos) for the full list. Core:

- [`jibar-os`](https://github.com/Jibar-OS/jibar-os) — this repo (manifest + docs)
- [`oird`](https://github.com/Jibar-OS/oird) — native inference daemon
- [`oir-framework-addons`](https://github.com/Jibar-OS/oir-framework-addons) — OIRService + AIDL
- [`oir-patches`](https://github.com/Jibar-OS/oir-patches) — 5 small patches to upstream AOSP
- [`oir-sdk`](https://github.com/Jibar-OS/oir-sdk) — Kotlin SDK for apps
- [`oir-demo`](https://github.com/Jibar-OS/oir-demo) — OirDemo Mission Control
- [`oir-vendor-models`](https://github.com/Jibar-OS/oir-vendor-models) — reference model bundle + fetch script
- [`device_google_cuttlefish`](https://github.com/Jibar-OS/device_google_cuttlefish) — reference device tree

External backend forks: [`platform_external_llamacpp`](https://github.com/Jibar-OS/platform_external_llamacpp), [`platform_external_whispercpp`](https://github.com/Jibar-OS/platform_external_whispercpp), [`platform_external_onnxruntime`](https://github.com/Jibar-OS/platform_external_onnxruntime).

---

## Status

Pre-1.0. Validated on Android 16 Cuttlefish with SELinux Enforcing. No real-device ports yet. **Looking for device contributors** — see [`CONTRIBUTING.md`](./CONTRIBUTING.md).

## License

Apache 2.0. See [`LICENSE`](./LICENSE) in each repo.
