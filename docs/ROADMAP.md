# JibarOS roadmap

**Last updated:** 2026-04-28

This is a living doc — open a discussion in [`Jibar-OS/JibarOS`](https://github.com/Jibar-OS/JibarOS/discussions) if you think something should be added, dropped, or re-prioritized.

---

## Critical fixes — not roadmap, do now

The daemon processes untrusted user input (image bytes, WAV files) on behalf of every app on the device. Hardening gaps that land outside any milestone — point-fix commits.

- **✅ JPEG decode crash on malformed input** — *shipped 2026-04-27 in `Jibar-OS/oird@d4ccfc0`*. Custom `jpeg_error_mgr` + `setjmp`/`longjmp` mirrors the existing PNG pattern. Smoke-tested on cvd: 18-byte garbage and a forged 50000x50000 header both rejected; oird stays alive.
- **✅ Image size cap** — *shipped 2026-04-27 in `Jibar-OS/oird@d4ccfc0`*. `image.max_pixels` knob (default 4096x4096 = 16M pixels = ~48 MB RGB; `0` disables) with overflow-safe `size_t` multiply. Documented in `KNOBS.md`.

Future critical-tier candidates land here.

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

### Daemon refactor + decomposition

✅ **COMPLETE — shipped 2026-04-28.** Two-phase rework. First a mechanical file split: `oird.cpp` went from 5,220 lines to 56 (main + binder lifecycle only); class declaration + AIDL glue moved to `service/`, capability bodies into `backend/{llama,whisper,vlm,ort}.cpp`, leaf utilities into `pool/`, `sched/`, `runtime/`, `tokenizer/`, `validation/`, `common/`. Then a real decomposition: cross-cutting state extracted into a `Runtime` struct, four real backend classes (`LlamaBackend`, `WhisperBackend`, `OrtBackend`, `VlmBackend`) each owning their capability bodies + knobs + per-handle pools, and a polymorphic `Resource` abstraction so eviction is a single registry walk instead of inline LRU loops in every load path.

End state:

```cpp
class Runtime { /* mLock, mModels, Budget, Scheduler, LoadRegistry, Resource registry, ... */ };
class LlamaBackend   { Runtime& mRt; ContextPool map; /* 12 knobs */ };
class WhisperBackend { Runtime& mRt; WhisperPool map; /* 4 knobs */ };
class OrtBackend     { Runtime& mRt; std::unique_ptr<Ort::Env>; /* mOcrRec + 19 knobs */ };
class VlmBackend     { Runtime& mRt; LlamaBackend& mLlama; /* 6 knobs */ };
class OirdService : BnOirWorker { Runtime mRt; <four backends>; /* AIDL methods are 1-line forwards */ };
```

**This is what unblocks v0.8 ObserveSession** — sessions implement `Resource`, override `pause()` to drop audio buffers + release pinned models without killing the session.

Per-commit detail (12-step decomposition arc, cleanup pass, binder thread pool auto-scaling, `setCapabilityFloat` dispatch chain) lives in [`oird/CHANGELOG.md`](https://github.com/Jibar-OS/oird/blob/main/CHANGELOG.md). Smoke-tested 5 capabilities on cvd after every commit; final clean rebuild 1m38, incremental rebuild after cleanup 23s.

### Pool + scheduler semantics

- ✅ **InFlightGuard RAII**, **empty-pool rejection at construction**, **FIFO tiebreaker** in `ContextPool::Waiter` ordering — all landed. See [`oird/CHANGELOG.md`](https://github.com/Jibar-OS/oird/blob/main/CHANGELOG.md) for hashes.
- **Document priority semantics honestly** — current strict-priority queue is bounded-wait, not starvation-free. Update `KNOBS.md` and consider adding a simple aging boost (`effectivePriority = base − ageMs/1000`) if real workloads report starvation.

### SDK stabilization

- Introduce an AIDL versioning scheme so the public contract can be frozen against breaking changes from v1.0 onward.
- Plan + start work toward an `oir-sdk` AAR distribution (Maven coordinate TBD).
- Audit the existing Java interop wrappers (`OirJavaText` / `OirJavaAudio` / `OirJavaVision`) for parity gaps with the Kotlin surface.

### Hardening carryover from v0.6

- ✅ `cmd oir dumpsys config` — surface resolved knobs at runtime (shipped post-v0.7-rc3 in `oir-framework-addons@a79c41f`; prints all 5 globals + per-capability tuning maps).
- `tools/fetch-models.sh` — cut a real GitHub Release with `voice-sample.wav` as an asset (worked around in v0.6.9 by committing in-tree).
- ✅ End-to-end `bootstrap.sh → m → launch_cvd` validation from a clean clone (shipped at v0.7-rc3; cvd boots with 6 capabilities RUNNABLE, OirDemo pre-installed, `cmd oir detect /product/etc/oir/bus.jpg` returns COCO boxes out of the box).
- 100-submit mixed-capability stress + `dumpsys memory` snapshot.
- Cross-backend scheduler "audio.* preempts text.*" live test.

### Observability

- ✅ `getMemoryStats()` extended — per-pool depth, busy count, waiting count, backend label per loaded model now in the structured `MemoryStats` parcelable. Shipped 2026-04-28 (`oir-framework-addons@6e4d73a` + `oird@74ad6bf`). Validated end-to-end on cvd: 6 concurrent submits vs pool=4 → `busy=4` reflected in `cmd oir memory` output. SDK consumers no longer need to call `dumpRuntimeStats` and TSV-parse.

### Drop the bake patches

`tools/jibar-os-bake.sh` currently applies 5 patches to upstream `frameworks/base/` files (`SystemServer.java`, `core/res/AndroidManifest.xml`, `core/res/Android.bp`, `core/res/res/values/strings.xml`, `services/core/Android.bp`) and 3 patches to `device/google/cuttlefish/` (`shared/device.mk`, `shared/sepolicy/system_ext/{file_contexts,service_contexts}`). 69 lines total. It works, but it mutates the user's working tree of upstream repos and is brittle on AOSP version bumps (context lines shift). Get this to zero by using AOSP's own extension mechanisms:

- **SystemServer registration via lifecycle framework** instead of patching `SystemServer.java` — `frameworks/base/services/core/java/com/android/server/SystemServiceManager` already supports declarative service lifecycles; ship `oir.rc` / `oir_services.xml` so the platform discovers `OIRService` without an inline patch.
- **Manifest + strings additions via `system_ext` APK overlay** instead of patching `core/res/AndroidManifest.xml` and `strings.xml` — overlay APKs land at `/system_ext/overlay/` and are merged at runtime by `OverlayManagerService`, no upstream patch needed.
- **`service_contexts` + `file_contexts` via vendor sepolicy fragment** instead of patching the cuttlefish device tree — vendor sepolicy already supports drop-in fragments at `/vendor/etc/selinux/`. Same trick for `device.mk`'s `PRODUCT_PACKAGES` — use a vendor mk include.
- **`Android.bp` additions** (the 2 lines that wire `oir_capabilities_xml` etc. into the framework build) — these can become Soong namespace mixins or simply move to the addon repo's own Android.bp.

End state: bake script just rsyncs `oir-framework-addons` into the tree (file additions, no in-place modifications). `vendor/jibar-os/oir-patches` repo deletes itself. Re-baselining on a new AOSP tag becomes a no-op for the JibarOS overlay.

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

