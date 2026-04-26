# JibarOS roadmap

**Last updated:** 2026-04-25

This is a living doc — open a discussion in [`Jibar-OS/JibarOS`](https://github.com/Jibar-OS/JibarOS/discussions) if you think something should be added, dropped, or re-prioritized.

---

## Critical fixes — not roadmap, do now

The daemon processes untrusted user input (image bytes, WAV files) on behalf of every app on the device. A few hardening gaps land outside any milestone — they should ship as point-fix commits as soon as someone picks them up:

- **JPEG decode crash on malformed input.** `image_decode.cpp` uses libjpeg with the default error handler. libjpeg's default behavior on fatal decode errors is to abort the process. A malformed JPEG from any app could DOS `oird`. Fix: install a custom `jpeg_error_mgr` with `setjmp`/`longjmp`, matching the pattern already used for PNG.
- **No max image size.** Both PNG and JPEG decode `resize((size_t)w * h * 3)` with no cap and no overflow check. A pathological image could exhaust memory in the daemon. Fix: enforce a `kMaxImagePixels` cap, check overflow before multiply, return `INVALID_INPUT` cleanly.

Treat as urgent — the daemon serves every app on the device, and untrusted-input crashes shouldn't wait for a milestone.

---

## Shipped

### v0.1 → v0.6.9 (2026-Q1 → 2026-04-23)

- **v0.1** — AOSP fork builds; `oird` daemon registered with `servicemanager`; AIDL surface defined.
- **v0.2** — First real inference. Qwen 2.5 0.5B via llama.cpp, isolated from `system_server`.
- **v0.3** — Capability-based dispatch + per-namespace permissions (`USE_TEXT` / `USE_AUDIO` / `USE_VISION`).
- **v0.4** — 7 capabilities live with permissive default models. Whisper + ONNX Runtime + libllava integrations.
- **v0.5** — `audio.vad` (Silero) + per-UID rate limits + OEM tuning knobs + libmtmd bump for modern VLMs.
- **v0.6** — `ContextPool` with priority-aware wait queue; KV-cache memory accounting; 4 new capabilities (`text.classify`, `text.rerank`, `text.translate`, `vision.ocr`); cross-backend scheduler. **12 capabilities total.**
- **v0.6.9** — Concurrent-load deadlock fix; in-progress dedup registry on both oird + OIRService sides; Fire All validated end-to-end on Cuttlefish (5 capabilities concurrent through OirDemo Fire All, zero hangs (6 RUNNABLE in dumpsys including a manually-warmed vision.describe)); public migration to the `Jibar-OS` GitHub org.

---

## v0.7 — daemon hardening + public surface

Target: tighten what we have. **No new capabilities.** Refactor the daemon, harden pool semantics, lock the public SDK contract, close v0.6 carryover.

### Daemon refactor

`oird.cpp` is ~4,900 lines today — pools, scheduler, tokenizer, all 12 capability handlers, ORT validation, phoneme parsing, model load registry, main(), all in one file. Split into:

```
system/oird/
├── oird.cpp                          ← main(), OirdService AIDL stubs (slim)
├── pool/
│   ├── context_pool.{h,cpp}          ← ContextPool + Lease + Waiter
│   └── whisper_pool.{h,cpp}          ← WhisperPool + WhisperLease
├── sched/
│   └── scheduler.{h,cpp}             ← cross-backend priority queue + worker pool
├── model/
│   ├── loaded_model.h
│   └── load_registry.{h,cpp}         ← LoadInProgress + claim/publish (v0.6.9 dedup)
├── backend/
│   ├── llama.{h,cpp}                 ← complete + embed + translate
│   ├── whisper.{h,cpp}               ← audio.transcribe
│   ├── vlm.{h,cpp}                   ← vision.describe via libmtmd
│   └── ort.{h,cpp}                   ← detect / vembed / vad / synthesize / classify / rerank / ocr
├── tokenizer/
│   ├── hf_tokenizer.{h,cpp}
│   └── phoneme_loader.{h,cpp}
├── validation/
│   └── ort_contract.{h,cpp}
├── common/{error_codes.h, types.h}
└── image_decode.{h,cpp}              ← already split
```

Mechanical refactor — preserve every public symbol, just relocate. Risk is contained if the 12 `submit*` smoke-tests still pass after.

### Pool + scheduler semantics

- **`InFlightGuard` RAII** for `inFlightCount`. Today's manual `++`/`--` paired with comments that say "callers must hold this" is exactly the invariant that breaks when someone adds a new submit method. RAII removes the trap.
- **Empty-pool rejection** at construction — return `MODEL_ERROR` at load time, not silent runtime failure on first submit.
- **FIFO tiebreaker** in `ContextPool::Waiter` ordering: `(priority, enqueueMs, id)` instead of `(priority, enqueueMs)`. Stable order when waiters land in the same millisecond.
- **Document priority semantics honestly** — current strict-priority queue is bounded-wait, not starvation-free. Update `KNOBS.md` and consider adding a simple aging boost (`effectivePriority = base − ageMs/1000`) if real workloads report starvation.

### SDK stabilization

- Introduce an AIDL versioning scheme so the public contract can be frozen against breaking changes from v1.0 onward.
- Plan + start work toward an `oir-sdk` AAR distribution (Maven coordinate TBD).
- Audit the existing Java interop wrappers (`OirJavaText` / `OirJavaAudio` / `OirJavaVision`) for parity gaps with the Kotlin surface.

### Hardening carryover from v0.6

- `cmd oir dumpsys config` — surface resolved knobs at runtime (currently requires scraping logcat).
- `tools/fetch-models.sh` — cut a real GitHub Release with `voice-sample.wav` as an asset (worked around in v0.6.9 by committing in-tree).
- End-to-end `repo init → bake.sh → m → launch_cvd` validation from a clean clone (not yet exercised by anyone outside the project).
- 100-submit mixed-capability stress + `dumpsys memory` snapshot.
- Cross-backend scheduler "audio.* preempts text.*" live test.
- `oir.permission.USE_CODE` formally declared (PM rejected the grant attempt during v0.6.9).

### Observability

- `getMemoryStats()` extended: per-pool depth, busy count, waiting count, backend label per loaded model. Pairs with v0.7 SDK telemetry surface.

---

## v0.8 — first device + `audio.observe` + `vision.observe`

Target: JibarOS boots end-to-end on a real device, and OIR adds **continuous-observation capabilities** alongside the existing one-shot ones.

### First real-device port

- **Pixel 8 / 8a / 9.** Well-documented hardware and a sane starting point for an AOSP-derivative OS.
- Bring-up doc + porting guide for additional devices.
- **A real device.** The single biggest accelerator on this milestone — see [Get involved](../README.md#get-involved). Sponsor a Pixel dev unit, donate one from a drawer, or wire us into a hardware partner program.
- cpuset latency study on real silicon — current `oird.rc` puts the daemon in `system-background`. Measure with/without; the right call may be device-class-dependent.

### Vulkan

- Vulkan acceleration for llama.cpp + libmtmd paths. Real-device GPUs are where this pays off; cuttlefish runs `gpu_mode=guest_swiftshader` and won't show meaningful gains.

### `audio.observe` — continuous listening

The OS-native version of "audio AI." Not a finished WAV in, transcript out — instead a **session that consumes mic frames as they arrive** and emits a structured event stream. The runtime gates expensive models behind cheap ones (VAD before transcribe; sound classifier before higher-level models) so the device isn't running whisper at 100% CPU on silence.

```kotlin
OpenIntelligence.audio.observe(
    AudioObserveOptions(
        vad = true,
        transcribe = true,
        classifySounds = true,
        partialTranscripts = true,
        language = "en"
    )
).collect { event ->
    when (event) {
        is AudioEvent.SpeechStarted     -> showListeningUI()
        is AudioEvent.PartialTranscript -> updateText(event.text)
        is AudioEvent.FinalTranscript   -> commitText(event.text)
        is AudioEvent.SoundClassified   -> showSoundLabel(event.label)
        is AudioEvent.ModelBusy         -> showBackpressureIndicator()
        is AudioEvent.FrameDropped      -> recordDropForDebug()
    }
}
```

The gated cascade is the load-bearing design choice:

```
mic stream
 → VAD (cheap, always on)
 → on speech: transcribe (expensive, only when VAD fires)
 → on classifier hit: higher-level (only when relevant)
silence / noise → drop
```

One-shot `audio.transcribe(file)` stays as the simple API. `audio.observe` is the realtime-cascade API for sensor-driven apps.

### `vision.observe` — continuous seeing

Same pattern for video. Session takes camera frames; the runtime drops frames it can't keep up with (`LATEST_WINS` policy by default) and emits a structured event stream of detection / description updates.

```kotlin
OpenIntelligence.vision.observe(
    VisionObserveOptions(
        detect = true,
        describeOnInteresting = true,
    )
).collect { event ->
    when (event) {
        is VisionEvent.Boxes        -> renderOverlay(event.boxes)
        is VisionEvent.Description  -> showCaption(event.text)
        is VisionEvent.MotionStop   -> dimOverlay()
        is VisionEvent.FrameDropped -> recordDropForDebug()
    }
}

// Feeding side
camera.frames.collect { frame -> session.feedFrame(frame) }
```

Gated cascade:
```
camera stream
 → motion detector (cheap, always on)
 → on motion: detect (medium, when frame changes)
 → on interesting object: describe (expensive, VLM)
static frames → drop
```

### Validation
- Reference benchmark suite for the four metrics from the README's "A benchmark we'd like to see exist" — resident capability count, see-think-speak latency, concurrent agent capacity, intelligence bandwidth.
- Power + thermal characterization on real silicon vs cuttlefish.
- SELinux Enforcing on real device with zero OIR-scoped AVC denials.
- Privapp-permissions XML sweep for the OIR-using app set.

---

## v1.0 — `world.observe` + stable contract

Target: the multimodal observation surface lands as a stable contract; the AIDL surface across `text.*` / `audio.*` / `vision.*` / `world.*` is frozen against further breaking changes.

### `world.observe` — multimodal session

A single session consumes both mic frames and camera frames, with timestamp-aligned events. The OS coordinates audio + video continuous intelligence as one stream — the surface multimodal agent apps need (see-and-hear assistants, AR overlays, body-cam scene narration, robot perception loops).

```kotlin
OpenIntelligence.world.observe(
    WorldObserveOptions(
        audio = AudioObserveOptions(vad = true, transcribe = true),
        video = VisionObserveOptions(detect = true, describe = true),
    )
).collect { event ->
    // events from BOTH modalities, with shared timeline
}
launch { mic.frames.collect    { session.feedAudio(it) } }
launch { camera.frames.collect { session.feedVideo(it) } }
```

### Stable contract

- AIDL surface frozen across `text.*`, `audio.*`, `vision.*`, `world.*` — including the observe shapes.
- OEM bake-in playbook documented end-to-end with worked examples.
- Compatibility test suite — anything claiming "JibarOS-compatible" passes a defined integration suite.
- Maven AAR public release of `oir-sdk`.

