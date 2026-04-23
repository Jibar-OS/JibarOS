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
| `vision.embed` | Vector | `USE_VISION` | `siglip-base-patch16-224.onnx` | ort | Model missing |
| `vision.describe` | TokenStream | `USE_VISION` | — (OEM-supplied VLM, pipe-delim `<mmproj>|<llm>`) | mtmd | ⚠️ No default |
| `vision.detect` | BoundingBoxes | `USE_VISION` | `rtdetr-r50vd-coco.onnx` | ort | ✅ Runnable |
| `vision.ocr` | BoundingBoxes | `USE_VISION` | — (OEM-supplied det+rec pair) | ort | ⚠️ No default |

- **✅ Runnable** — reference Cuttlefish build boots with this capability immediately.
- **⚠️ No default** — capability declared, but the permissive-license landscape has no universal default. OEMs bake their choice.
- **Model missing** — reference model is declared in `capabilities.xml`, but the permissive-license binary isn't bundled today. OEMs or contributors supply.

## Capability variants

A capability name may have a `:variant` suffix. Example: `text.complete:quality` can declare a different default-model than `text.complete:fast`. Both routes through the same shape + backend. Useful for OEMs that want to offer multiple tiers without forcing apps to hardcode model paths.

The SDK's `OpenIntelligence.text.completeStream(prompt, options, capability = "text.complete:fast")` takes the variant as an argument. If the variant doesn't exist on the device, it falls back to the base capability (`text.complete`).

## Runnability

`cmd oir dumpsys capabilities` lists every registered capability with its runnability status:

```
text.complete         [RUNNABLE]
text.embed            [RUNNABLE]
audio.transcribe      [RUNNABLE]
vision.describe       [NO_DEFAULT_MODEL]   ← declared, no bundled path
vision.detect         [RUNNABLE]
vision.ocr            [NO_DEFAULT_MODEL]
audio.synthesize      [MODEL_MISSING]      ← path declared but file absent
```

Apps can check programmatically via `OpenIntelligence.isCapabilityRunnable("audio.transcribe")` which returns one of `RUNNABLE`, `NO_DEFAULT_MODEL`, `MODEL_MISSING`, `CAPABILITY_NOT_FOUND`. Use this to show/hide features cleanly instead of guessing.

## Reserved namespaces

The following prefixes are reserved for platform-declared capabilities. OEMs cannot declare new entries under these:

- `text.` / `audio.` / `vision.` / `code.`
- `oir.` / `android.` / `os.`

OEMs extend via reverse-DNS (`com.oem.xxx`). Required-permission is OEM-declared in their fragment at `/vendor/etc/oir/*.xml`.

## See also

- [`KNOBS.md`](./KNOBS.md) — per-capability tuning knobs
- [`MODELS.md`](./MODELS.md) — which model goes where, licenses, how to bake
- [`SDK.md`](./SDK.md) — how apps call capabilities
