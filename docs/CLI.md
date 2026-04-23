# `cmd oir` — shell command reference

OIR exposes a shell command surface via `system_server`. Every subcommand below is implemented in [`OIRShellCommand.java`](https://github.com/Jibar-OS/oir-framework-addons/blob/main/frameworks/base/services/core/java/com/android/server/oir/OIRShellCommand.java) — the canonical source of truth.

```bash
adb shell cmd oir help
```

prints a one-line summary per subcommand. This doc is the longer version.

## Capability dispatch

These subcommands smoke-test each capability end-to-end. They go through the same AIDL surface apps use — same permission checks, same rate limits, same error mapping.

### `cmd oir submit "<prompt>"`

text.complete (default) — streams the response token by token to stdout.

```bash
adb shell cmd oir submit "Summarize Android 16 in one sentence."
```

Flags:

- `--cap <capability>` — route to a specific capability (e.g. `text.translate`).
- `--as-uid <uid>` — submit as a different UID for permission/rate-limit testing (`userdebug` only; ignored on `user` builds).

Output:

```
--- start handle=42 backend=oird
Android 16 introduces …
--- done tokens=27 firstTokenMs=140 totalMs=2410
```

Exit code: 0 on success, 1 on error / timeout.

### `cmd oir embed <text>`

text.embed — emits a single pooled vector. Prints dim + first 8 / last 4 components.

### `cmd oir classify <text>`

text.classify — emits per-label scores. OEM-supplied model required.

### `cmd oir rerank <query> <candidate1> [<candidate2> …]`

text.rerank — score per candidate.

### `cmd oir translate [--src <lang>] [--tgt <lang>] <text>`

text.translate — streams the translated text. Defaults src=auto, tgt=en.

### `cmd oir transcribe <wav-path>`

audio.transcribe — streams whisper segments. WAV must be 16-bit mono 16 kHz; the runtime validates and surfaces `INVALID_INPUT` otherwise.

### `cmd oir synthesize "<text>" [<out.raw>]`

audio.synthesize — streams Piper PCM chunks. With `out.raw`, writes PCM to the file. Without, prints sample count + rate to stdout.

Requires the Piper voice's `<voice>.phonemes.json` G2P sidecar at the same path as the `.onnx` model.

### `cmd oir vad <pcm-path>`

audio.vad — streams voice-on / voice-off transitions with millisecond timestamps. Input is raw 16-bit mono 16 kHz PCM.

### `cmd oir describe <image-path> [<prompt>]`

vision.describe — streams a VLM caption. With prompt, instructs the VLM (e.g. `"What is in this image?"`); without, the VLM uses its default prompt.

### `cmd oir detect <image-path>`

vision.detect — emits bounding boxes. Output: one line per box with `(x, y, w, h)  label  score`.

### `cmd oir ocr <image-path>`

vision.ocr — emits bounding boxes with recognized text in the label field.

### `cmd oir vembed <image-path>`

vision.embed — emits the pooled image embedding vector. Same output shape as `cmd oir embed`.

## Lifecycle + introspection

### `cmd oir warm <capability>`

Lazy-loads the capability's default model (or the OEM override) without dispatching a request. Useful for benchmarking — separates load time from inference time. Idempotent.

```bash
adb shell cmd oir warm text.complete
adb shell cmd oir warm vision.describe
```

### `cmd oir dumpsys [capabilities]`

(`capabilities` is the default and only target; bare `dumpsys` works the same.)

Lists every registered capability with its runnability status, shape, required permission, declared default model, backend, and source XML. Closes with a summary line.

```
OIR capabilities (12 total):
  text.complete  [RUNNABLE]
      shape:    TokenStream
      perm:     oir.permission.USE_TEXT
      model:    /product/etc/oir/qwen2.5-0.5b-instruct-q4_k_m.gguf
      backend:  llama
      source:   /system_ext/etc/oir/capabilities.xml
  text.embed  [RUNNABLE]
      …
  vision.describe  [NO_DEFAULT_MODEL]
      shape:    TokenStream
      perm:     oir.permission.USE_VISION
      model:    (none — OEM must bake)
      backend:  mtmd
      source:   /system_ext/etc/oir/capabilities.xml

Summary: 6 runnable, 3 unbacked, 3 model-missing
```

Status values:

| Status | Meaning |
|---|---|
| `RUNNABLE` | Default model file exists at the declared path. |
| `NO_DEFAULT_MODEL` | Capability declared but no `default-model` attribute (OEM must supply). |
| `MODEL_MISSING` | `default-model` declared, but the file isn't on the device. |
| `UNKNOWN` | Runtime-side check failed (very rare; usually a binder timeout). |

### `cmd oir memory`

Runtime memory snapshot — per-loaded-model resident bytes, KV-cache estimate, last-access timestamp, in-flight count, and the total resident vs the configured budget. Dispatches to oird's `getMemoryStats()`.

### `cmd oir help` / `-h` / `--help`

One-line summary of every subcommand.

## Permissions on `userdebug` vs `user` builds

`cmd oir` runs as the SHELL UID (2000), which holds every `oir.permission.USE_*` by design — so smoke-tests don't need a privileged test app. Two consequences:

- **Rate limits do not apply** to `cmd oir` calls. The per-UID token-bucket explicitly bypasses SHELL_UID. Use a real test APK to validate rate-limit behavior.
- **Permission denials don't fire** unless you pass `--as-uid <some-other-uid>`. The `--as-uid` flag is only honored on `userdebug` builds.

## Exit codes

- `0` — success.
- `1` — usage error, AIDL error, runtime error, or timeout.

## See also

- [`CAPABILITIES.md`](./CAPABILITIES.md) — capability shapes, default models, permissions.
- [`KNOBS.md`](./KNOBS.md) — runtime tuning via `oir_config.xml`.
- [`MODELS.md`](./MODELS.md) — model bake-in and OEM overrides.
