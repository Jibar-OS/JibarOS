<p align="center">
  <img src="assets/banner.png" alt="JibarOS" width="100%"/>
</p>

<p align="center">
  <a href="https://www.loom.com/share/a4de8aa1666e4b9a8efa128f98b7f16c">
    <img src="https://cdn.loom.com/sessions/thumbnails/a4de8aa1666e4b9a8efa128f98b7f16c-7826565414152998-full-play.gif"
         alt="v0.6.9 Fire All demo — Loom"
         width="720"/>
  </a>
</p>

<p align="center">
  <em>v0.6.9 Fire All on Cuttlefish — 6 capabilities streaming concurrently through the OIR platform service. <a href="https://www.loom.com/share/a4de8aa1666e4b9a8efa128f98b7f16c">Watch the full ~2 min recording</a>.</em>
</p>

# JibarOS

**An Android-derivative OS with a multi-backend AI runtime at the platform layer.**

JibarOS is an AOSP fork. One system service (`OIRService`) + one native daemon (`oird`) expose **12 AI capabilities** — text, audio, vision — to every app on the device through a single AIDL surface. Models load once at the platform tier and are shared across callers. Backends are pluggable per capability (llama.cpp, whisper.cpp, ONNX Runtime, libmtmd). OEMs pick which model serves each capability on their product; apps don't care.

Named after Puerto Rico's *jíbaros* — rural folk, known for resilience and self-sufficiency. Models and runtime live on the device, work offline, no cloud account required.

> ⭐ **Like what you see? Star this repo** — it's the cheapest signal that on-device AI belongs at the platform tier, and it helps the right contributors find the project.

---

## The short version

```
┌────────────────────────────────────────────────────────────────┐
│  Apps (any UID)                                                 │
│  Oir.text.completeStream(...) / Oir.audio.transcribeStream(...)│
│           │ Oir.vision.describe(...) / Oir.vision.detect(...)  │
│           ▼                                                     │
├────────────────────────────────────────────────────────────────┤
│  OIRService (system_server)                                     │
│  ├─ enforces oir.permission.USE_TEXT / USE_AUDIO / USE_VISION   │
│  ├─ per-UID rate limiting                                       │
│  ├─ capability registry (capabilities.xml + OEM fragments)      │
│  └─ dispatches to oird over IOirWorker AIDL                     │
├────────────────────────────────────────────────────────────────┤
│  oird (native daemon, /system_ext/bin/oird)                     │
│  ├─ shared model residency                                      │
│  ├─ ContextPool / WhisperPool (priority-aware wait queues)      │
│  ├─ KV-cache memory accounting + LRU eviction                   │
│  └─ cross-backend scheduler with per-capability priority        │
├────────────────────────────────────────────────────────────────┤
│  Backends                                                        │
│  llama.cpp  │  whisper.cpp  │  ONNX Runtime  │  libmtmd         │
│  (GGUFs)    │  (.bin)       │  (.onnx)       │  (VLMs)         │
└────────────────────────────────────────────────────────────────┘
```

Three ideas:

1. **Capability, not tensor.** Apps ask for `text.complete` or `vision.describe`. They don't touch tensors or runtimes. The platform owns the inference graph.
2. **One loaded model per capability, shared across every caller.** If three apps all want `text.complete`, the GGUF loads once. KV cache is budgeted. Contexts are pooled.
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

## How OEMs pick models

JibarOS declares the capability contract; OEMs pick the backing model. Two ways:

**Platform bake-in** — the reference Cuttlefish build ships 5 permissive defaults via [`oir-vendor-models`](https://github.com/Jibar-OS/oir-vendor-models) (Apache 2.0 + MIT). `PRODUCT_PACKAGES += oir_default_model oir_minilm_model oir_whisper_tiny_en_model …` wires them into `/product/etc/oir/`.

**Per-OEM override** — `/vendor/etc/oir/oir_config.xml` overrides the default model per capability. Example:

```xml
<oir_config>
  <capability_tuning>
    <capability name="vision.describe">
      <default_model>/product/etc/oir/mmproj.gguf|/product/etc/oir/llm.gguf</default_model>
    </capability>
  </capability_tuning>
</oir_config>
```

The OEM can swap LLaVA-1.5-7B for SmolVLM-500M for a thin device — no framework changes, no app changes.

Full guide: [`docs/MODELS.md`](./docs/MODELS.md).

---

## Runtime + memory management

Every app calling `Oir.text.completeStream` touches the SAME loaded model. That model has a **context pool** with N slots (default 4 for `text.complete`); each slot is an independent `llama_context` with its own KV cache. Concurrent submits interleave at the slot level.

**Budget accounting.** Every loaded model reports weights + pool KV cache in its resident footprint. When a new load would exceed the configured memory budget, LRU eviction runs — skipping models that are in-flight or inside a `warm()` TTL window.

**Priority-aware queues.** `audio.*` capabilities default to `AUDIO_REALTIME`; everything else to `NORMAL`. Queued audio submits jump ahead of queued text submits within a shared pool. Priority is queue-order, not preemption — a long in-flight completion runs to completion.

**Concurrency proof.** [`v0.6.9` Fire All](./docs/CAPABILITIES.md) validated on Cuttlefish: 5 concurrent `load*()` calls (text.complete, text.embed, audio.transcribe, vision.detect, vision.describe) all resolved without hangs, 6 capabilities streamed simultaneously.

---

## Tuning knobs

OEMs tune per-capability behavior via `/vendor/etc/oir/oir_config.xml`. Global knobs: memory budget, warm TTL, inference timeout, rate limits. Per-capability: context window, max tokens, contexts-per-model, acquire timeout, priority, temperature, top-p, preprocess sizes, detection thresholds.

Full reference: [`docs/KNOBS.md`](./docs/KNOBS.md).

---

## SDK

Apps consume OIR via the [`oir-sdk`](https://github.com/Jibar-OS/oir-sdk) Kotlin library:

```kotlin
import com.oir.Oir

Oir.text.completeStream("Summarize this in one sentence: …")
    .collect { chunk -> print(chunk.text) }

val vector: FloatArray = Oir.text.embed("vector me")

Oir.audio.transcribeStream("/sdcard/voice.wav")
    .collect { chunk -> println(chunk.text) }

val boxes = Oir.vision.detect("/sdcard/photo.jpg")
```

Structured concurrency, typed errors, Java interop. Full guide: [`docs/SDK.md`](./docs/SDK.md).

---

## AAOSP → JibarOS

This project builds directly on [**AAOSP**](https://github.com/rufolangus/AAOSP) — the earlier AOSP fork that first put an LLM inside `system_server` as a platform service (`LlmManagerService`) and introduced MCP tool-calling at the manifest layer.

AAOSP proved the core insight: **on-device AI belongs at the platform tier, not bundled per-app.** Any app with an `<mcp-server>` declaration becomes reachable by the platform LLM. HITL consent + audit is a platform invariant. Every idea about "AI is infrastructure" in this project traces back to AAOSP.

JibarOS extends that pattern to a **broader runtime surface**. Where AAOSP's `LlmManagerService` is purpose-built for MCP tool-calling with one llama.cpp LLM, OIR is the general inference layer: 12 capabilities across text/audio/vision, four pluggable backends (llama.cpp / whisper.cpp / ONNX Runtime / libmtmd), pooled residency, KV budget, cross-backend priority scheduler. An AAOSP-style MCP agent, or any other agent framework, could sit on top of OIR and use it as the inference substrate — that's what "mechanism, not policy" means in practice.

Complement, not replacement.

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

---

## Status

Pre-1.0. Validated on Android 16 Cuttlefish with SELinux Enforcing. No real-device ports yet. **Looking for device contributors** — see [`CONTRIBUTING.md`](./CONTRIBUTING.md).

## License

Apache 2.0. See [`LICENSE`](./LICENSE) in each repo.
