# OIR capabilities

The 12 capabilities shipped in v0.6.9. Each has a fixed *shape* (input/output AIDL contract) and a pluggable *backend model*. Apps target capability names; OEMs bake backing models.

## Shapes

| Shape | Description | Example capabilities |
|---|---|---|
| `TokenStream` | Streams tokens via `IOIRTokenCallback.onToken(String, int outputIndex)` until terminal `onComplete` or `onError`. | `text.complete`, `text.translate`, `audio.transcribe`, `vision.describe` |
| `Vector` | One-shot — `IOIRVectorCallback.onVector(float[])` emits a fixed-length embedding or score vector. | `text.embed`, `text.classify`, `text.rerank`, `vision.embed` |
| `AudioStream` | Streams PCM chunks via `IOIRAudioStreamCallback.onChunk(byte[], sampleRateHz, channels, encoding, isLast)`. | `audio.synthesize` |
| `RealtimeBoolean` | Streams on/off transitions via `IOIRRealtimeBooleanCallback.onState(boolean, timestampMs)`. | `audio.vad` |
| `BoundingBoxes` | One-shot — `IOIRBoundingBoxCallback.onBoundingBoxes(List<BoundingBox>)`. | `vision.detect`, `vision.ocr` |

## Capability table

| Capability | Shape | Permission | Default model | Backend | Status |
|---|---|---|---|---|---|
| `text.complete` | TokenStream | `USE_TEXT` | `qwen2.5-0.5b-instruct-q4_k_m.gguf` | llama | ✅ Runnable |
| `text.translate` | TokenStream | `USE_TEXT` | `qwen2.5-0.5b-instruct-q4_k_m.gguf` (shared) | llama | ✅ Runnable |
| `text.embed` | Vector | `USE_TEXT` | `all-MiniLM-L6-v2.Q8_0.gguf` | llama | ✅ Runnable |
| `text.classify` | Vector | `USE_TEXT` | — (OEM-supplied) | ort | ⚠️ No default |
| `text.rerank` | Vector | `USE_TEXT` | `ms-marco-minilm-l6-v2.onnx` | ort | Model missing |
| `audio.transcribe` | TokenStream | `USE_AUDIO` | `whisper-tiny-en.Q5.bin` | whisper | ✅ Runnable |
| `audio.synthesize` | AudioStream | `USE_AUDIO` | `piper-en-us-amy-low.onnx` + `.phonemes.json` sidecar | ort | Model + sidecar needed |
| `audio.vad` | RealtimeBoolean | `USE_AUDIO` | `silero_vad.onnx` | ort | Model missing |
| `vision.embed` | Vector | `USE_VISION` | `siglip-base-patch16-224.onnx` | ort | ✅ Runnable |
| `vision.describe` | TokenStream | `USE_VISION` | — (OEM-supplied VLM, pipe-delim `<mmproj>|<llm>`) | mtmd | ⚠️ No default |
| `vision.detect` | BoundingBoxes | `USE_VISION` | `rtdetr-r50vd-coco.onnx` | ort | Model missing |
| `vision.ocr` | BoundingBoxes | `USE_VISION` | — (OEM-supplied det+rec pair) | ort | ⚠️ No default |

- **✅ Runnable** — reference Cuttlefish build boots with this capability immediately. The 4 bundled models (Qwen 0.5B, MiniLM, whisper-tiny-en, SigLIP-base) plus the Qwen-shared translate cover **5 of the 12 capabilities**.
- **⚠️ No default** — capability declared, but the permissive-license landscape has no universal default. OEMs bake their choice.
- **Model missing** — reference model is declared in `capabilities.xml`, but the permissive-license binary isn't bundled today. OEMs or contributors supply (or add to `oir-vendor-models/tools/fetch-models.sh`).

## Capability variants

A capability name may have a `:variant` suffix (matching `[a-z0-9_]{1,32}`). The reference `capabilities.xml` declares two:

```xml
<capability name="text.complete:fast"    ... default-model="<small/quantized model>" />
<capability name="text.complete:quality" ... default-model="<larger/higher-quality model>" />
```

**The thinking:** the same capability name (e.g., `text.complete`) can have multiple deployed model configurations on a single device that trade off latency vs. quality. OEMs declare the tiers; apps that care about latency target `:fast`, apps that care about quality target `:quality`. Both routes go through the same AIDL shape and backend dispatcher.

This decouples app code from model paths — apps don't have to know which GGUF a vendor shipped, just which TIER they want. A device with only the base capability declared (no variants) still serves all calls via `text.complete`.

### Planned SDK shape (v0.7 — NOT YET WIRED)

```kotlin
// PLANNED — TextCapabilitiesImpl does NOT accept this argument today.
// Tracking this here so we don't forget to wire it.
OpenIntelligence.text.completeStream(
    prompt,
    options,
    capability = "text.complete:fast"  // or "text.complete:quality"
)
```

If the requested variant doesn't exist on the device, the call should fall back to the base capability (`text.complete`) — not error with `CAPABILITY_NOT_FOUND`. The variant declarations in `capabilities.xml` already exist as a forward-compatibility surface so OEMs can prepare model bundles ahead of the SDK landing.

Today the SDK routes every `OpenIntelligence.text.completeStream(...)` call to the base `text.complete` capability. Apps cannot programmatically request `:fast` or `:quality` until the v0.7 SDK work lands.

## Runnability

`cmd oir dumpsys capabilities` lists every registered capability with its runnability status:

```
text.complete         [RUNNABLE]
text.translate        [RUNNABLE]
text.embed            [RUNNABLE]
audio.transcribe      [RUNNABLE]
vision.embed          [RUNNABLE]
text.classify         [NO_DEFAULT_MODEL]   ← declared, no bundled path
vision.describe       [NO_DEFAULT_MODEL]
vision.ocr            [NO_DEFAULT_MODEL]
text.rerank           [MODEL_MISSING]      ← path declared but file absent
audio.synthesize      [MODEL_MISSING]
audio.vad             [MODEL_MISSING]
vision.detect         [MODEL_MISSING]
```

Summary on a clean Cuttlefish boot: 5 RUNNABLE, 3 NO_DEFAULT_MODEL, 4 MODEL_MISSING.

Apps can check programmatically via `OpenIntelligence.isCapabilityRunnable("audio.transcribe")` which returns one of `RUNNABLE`, `NO_DEFAULT_MODEL`, `MODEL_MISSING`, `CAPABILITY_NOT_FOUND`. Use this to show/hide features cleanly instead of guessing.

## Reserved namespaces

The following prefixes are reserved for platform-declared capabilities. OEMs cannot declare new entries under these:

- `text.` / `audio.` / `vision.`
- `oir.` / `android.` / `os.`

OEMs extend via reverse-DNS (`com.oem.xxx`). Required-permission is OEM-declared in their fragment at `/vendor/etc/oir/*.xml`.

## See also

- [`KNOBS.md`](./KNOBS.md) — per-capability tuning knobs
- [`MODELS.md`](./MODELS.md) — which model goes where, licenses, how to bake
- [`SDK.md`](./SDK.md) — how apps call capabilities
