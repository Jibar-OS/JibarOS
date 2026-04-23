# OIR tuning knobs

OEMs configure runtime behavior via `/vendor/etc/oir/oir_config.xml`. Two classes of knob:

1. **Global knobs** — apply to the whole runtime.
2. **Per-capability knobs** — apply to one capability (`text.complete.n_ctx`, etc.).

All knobs have sensible defaults — an OEM shipping an unmodified JibarOS runtime without any config XML gets the table-of-defaults behavior below.

## File format

```xml
<?xml version="1.0" encoding="utf-8"?>
<oir_config>
    <!-- Global knobs: single value per tag -->
    <memory_budget_mb>4096</memory_budget_mb>
    <warm_ttl_seconds>60</warm_ttl_seconds>
    <inference_timeout_seconds>120</inference_timeout_seconds>
    <rate_limit_per_minute>60</rate_limit_per_minute>
    <rate_limit_burst>10</rate_limit_burst>

    <!-- Per-capability knobs: nested -->
    <capability_tuning>
        <capability name="text.complete">
            <n_ctx>4096</n_ctx>
            <max_tokens>512</max_tokens>
            <temperature>0.7</temperature>
            <top_p>0.9</top_p>
            <contexts_per_model>4</contexts_per_model>
            <acquire_timeout_ms>30000</acquire_timeout_ms>
            <priority>NORMAL</priority>
        </capability>

        <capability name="vision.describe">
            <default_model>/product/etc/oir/mmproj.gguf|/product/etc/oir/llm.gguf</default_model>
            <n_ctx>4096</n_ctx>
            <n_batch>2048</n_batch>
            <max_tokens>256</max_tokens>
            <contexts_per_model>1</contexts_per_model>
            <acquire_timeout_ms>60000</acquire_timeout_ms>
        </capability>
    </capability_tuning>
</oir_config>
```

Load order:
1. `/system_ext/etc/oir/oir_config.xml` — platform defaults (usually absent).
2. `/vendor/etc/oir/oir_config.xml` — OEM overrides (last-writer-wins per key).

## Global knobs

| Knob | Default | Unit | Notes |
|---|---|---|---|
| `memory_budget_mb` | `4096` | MB | Resident-memory budget. `0` disables the check (unlimited). When load would exceed this, LRU eviction runs (skipping in-flight + warmed models). |
| `warm_ttl_seconds` | `60` | seconds | How long `warm()` protects a model from eviction after an explicit warm. |
| `inference_timeout_seconds` | `120` | seconds | Per-request wall-clock cap before oird fires `TIMEOUT` error. |
| `rate_limit_per_minute` | `60` | reqs / min per UID | Token-bucket refill rate. |
| `rate_limit_burst` | `10` | reqs | Token-bucket capacity. SHELL_UID bypasses rate-limit by design. |

## Per-capability knobs

All keys are `capability_name.knob_name` under the hood (e.g. `text.complete.n_ctx`). Unknown keys are silently ignored — forward-compat safe.

### Text / vision-describe (llama / mtmd backends)

| Knob | Default | Applies to | Notes |
|---|---|---|---|
| `n_ctx` | `2048` (text.complete), `512` (text.embed), `4096` (vision.describe) | llama + mtmd | Context window size. Embed can be shorter — typical input is a sentence. |
| `n_batch` | `2048` (vision.describe only) | mtmd | Logical batch size for prompt processing. Image-prompt VLMs need larger batches; 2048 covers LLaVA-scale (576 image patches + prompt). |
| `max_tokens` | `256` (text.complete, vision.describe) | TokenStream caps | Upper bound if caller doesn't override. |
| `temperature` | `0.7` | text.complete | Sampling temp default. Callers can pass a custom one per-request via `CompletionOptions`. |
| `top_p` | `0.9` | text.complete | Nucleus sampling cutoff. |
| `contexts_per_model` | `4` (text.complete), `2` (text.embed), `1` (vision.describe) | llama + mtmd `ContextPool` | How many parallel inference contexts share a loaded model. Higher = more concurrency + more KV-cache memory. VLMs default to 1 because a single context is 500 MB+ of KV. |
| `acquire_timeout_ms` | `30000` (text.complete), `10000` (text.embed), `60000` (vision.describe) | ContextPool bounded-wait | If every context is busy longer than this, new requests fail with `TIMEOUT`. |
| `priority` | `NORMAL` for text; `AUDIO_REALTIME` for audio.* | Pool wait queue ordering | `INTERACTIVE > AUDIO_REALTIME > NORMAL > LOW`. A high-priority queued request jumps ahead of other queued requests in the same pool. **Priority is queue-order, not preemption** — a long in-flight request runs to completion. |

### Audio backends

| Knob | Default | Applies to | Notes |
|---|---|---|---|
| `contexts_per_model` | `2` | `audio.transcribe` WhisperPool | Parallel whisper contexts per model. Kernel COW-shares the weights mmap, so extra cost is just per-ctx state (~tens of MB for whisper-tiny). |
| `acquire_timeout_ms` | `30000` | `audio.transcribe` | Same story as above. |
| `whisper_language` | auto-detect | `audio.transcribe` | Forces a specific whisper language code (e.g. `en`, `es`, `auto`). |

### Vision backends

| Knob | Default | Applies to | Notes |
|---|---|---|---|
| `input_size` | `640` (vision.detect), `224` (vision.embed) | preprocess target resolution | Pixels; preprocess resizes to `input_size × input_size`. Must match the ONNX model's expected input. |
| `norm_mean` | `0.5f` (vision.embed) | preprocess | Per-channel mean subtracted before inference. SigLIP uses 0.5. |
| `norm_std` | `0.5f` (vision.embed) | preprocess | Per-channel std divisor. SigLIP uses 0.5. |
| `score_threshold` | `0.25f` (vision.detect) | NMS | Detections below this confidence are dropped. |
| `iou_threshold` | `0.45f` (vision.detect) | NMS | Boxes overlapping more than this are merged. |
| `family` | `rtdetr` (vision.detect) | detection parser | `rtdetr` / `yolov8`. Toggles output-tensor interpretation. |

### VAD (`audio.vad`)

| Knob | Default | Notes |
|---|---|---|
| `voice_threshold` | `0.5` | Probability cutoff for voice-present. |
| `sample_rate_hz` | `16000` | Silero v5 expects 16 kHz. 8 kHz models need this override. |
| `window_samples` | `512` | Per-window sample count. |
| `context_samples` | `64` | Context samples prepended to each window. Input tensor length is `context + window`. |

### Default-model override (v0.6.9 — capabilities without a platform default)

For capabilities declared in `capabilities.xml` with no `default-model` attribute (`vision.describe`, `text.classify`, `vision.ocr`), OEMs supply a model via the tuning-knob escape hatch:

```xml
<capability name="vision.describe">
    <default_model>/product/etc/oir/mmproj.gguf|/product/etc/oir/llm.gguf</default_model>
</capability>
```

The `CapabilityRegistry.applyConfigOverrides()` merges this in at service startup. Only applies when the platform capability has no default — OEMs cannot shadow a platform-bundled model.

## Querying applied knobs at runtime

```
adb shell cmd oir dumpsys config
```

Dumps every resolved knob with its source (`default` / `platform XML` / `OEM XML`). Helpful when a capability behaves unexpectedly — see which knob is driving it.

## See also

- [`CAPABILITIES.md`](./CAPABILITIES.md) — the 12 capabilities these knobs tune
- [`MODELS.md`](./MODELS.md) — OEM model bake-in + install paths
