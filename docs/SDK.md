# OIR SDK

Kotlin SDK that apps depend on to call OIR capabilities. Lives at [`oir-sdk`](https://github.com/Jibar-OS/oir-sdk).

## Install

### Coming from JibarOS (platform-signed priv-app)

```soong
android_app {
    name: "MyOirApp",
    srcs: ["src/**/*.kt"],
    platform_apis: true,
    privileged: true,
    certificate: "platform",
    static_libs: [
        "oir_sdk",
        "oir_sdk_aosp",         // AIDL companion — provides the binder adapter
        "kotlinx-coroutines-android",
    ],
}
```

### Third-party apps

Apps declaring `<uses-permission android:name="oir.permission.USE_TEXT" />` (etc.) on a JibarOS device can consume the SDK via the published AAR (ships as part of the JibarOS SDK distribution, TBD).

## Permissions

Declare in your `AndroidManifest.xml`:

```xml
<uses-permission android:name="oir.permission.USE_TEXT"   />
<uses-permission android:name="oir.permission.USE_AUDIO"  />
<uses-permission android:name="oir.permission.USE_VISION" />
```

`oir.permission.USE_*` are signature|privileged permissions. Platform-signed apps auto-grant; others need manual grant via PackageManager (OEM-specific flow).

## Public surface

Everything hangs off the `Oir` object.

```kotlin
import com.oir.Oir
import android.app.Application

class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Oir.installContext(this)       // one-time bootstrap per process
    }
}
```

Three top-level namespaces:

```kotlin
Oir.text     // text.complete, text.translate, text.embed, text.classify, text.rerank
Oir.audio    // audio.transcribe, audio.synthesize, audio.vad
Oir.vision   // vision.describe, vision.detect, vision.embed, vision.ocr
```

Plus one utility:

```kotlin
Oir.isCapabilityRunnable("audio.transcribe")
    // → CapabilityStatus.RUNNABLE / NO_DEFAULT_MODEL / MODEL_MISSING / CAPABILITY_NOT_FOUND
```

## Examples

### Streaming text completion

```kotlin
import kotlinx.coroutines.flow.*

val options = CompletionOptions(maxTokens = 128, temperature = 0.7f)
Oir.text.completeStream("Summarize in one sentence: …", options)
    .onEach { chunk -> print(chunk.text) }   // Flow<TextChunk>
    .collect {}
```

### One-shot text embedding

```kotlin
val vec: FloatArray = Oir.text.embed("vector me")
// vec.size == 384 for MiniLM
```

### Audio transcription from a WAV file

```kotlin
Oir.audio.transcribeStream("/product/etc/oir/voice-sample.wav")
    .collect { chunk -> println(chunk.text) }
```

The WAV must be **16-bit PCM, mono, 16 kHz**. The SDK validates this before sending and throws `OirInvalidInputException` on mismatch.

### Vision describe (VLM)

```kotlin
Oir.vision.describeStream(
    imagePath = "/sdcard/Pictures/photo.jpg",
    prompt    = "What is happening in this image?",
    options   = DescribeOptions(maxTokens = 256),
).collect { chunk -> print(chunk.text) }
```

### Object detection (one-shot)

```kotlin
val objects: List<DetectedObject> = Oir.vision.detect(
    imagePath = "/sdcard/Pictures/photo.jpg",
)
// each DetectedObject has (x, y, width, height, label, score)
```

## Cancellation

Every suspend/Flow is structured-concurrency-aware. Cancel by cancelling the coroutine:

```kotlin
val job = lifecycleScope.launch {
    Oir.text.completeStream("…").collect { /* … */ }
}
// Later…
job.cancel()   // Streams stop, oird cleans up the in-flight request.
```

Under the hood, cancellation sends `ICancellationSignal.cancel()` to OIRService → oird, which aborts the current `llama_decode` / `whisper_full` / `ORT::Run` loop at the next checkpoint.

## Error model

Every SDK call throws subclasses of `OirException`:

| Exception | Meaning | Typical cause |
|---|---|---|
| `OirInvalidInputException` | Input failed validation | Wrong WAV format, empty prompt, missing file |
| `OirModelErrorException` | Model load / inference failed | GGUF corrupt, ONNX shape mismatch |
| `OirCapabilityUnavailableException` | Capability declared but no model available | `MODEL_MISSING` or `NO_DEFAULT_MODEL` state |
| `OirPermissionDeniedException` | Missing `oir.permission.USE_*` | Not platform-signed, not granted |
| `OirWorkerUnavailableException` | oird not reachable | Worker crashed mid-flight / not attached yet |
| `OirRateLimitedException` | Per-UID rate limit tripped | >60 reqs/min sustained |
| `OirCancelledException` | Cancelled via coroutine cancellation | Expected; swallow or re-throw |

Streaming APIs throw from within their Flow; catch via `try { … } catch (e: OirException) { … }` around the `.collect {}`.

## Testing

The SDK ships a fake implementation for unit tests:

```kotlin
import com.oir.testing.OirFake
import com.oir.testing.OirTestRule

class MyTest {
    @get:Rule val oirRule = OirTestRule()

    @Test fun completeStream_emitsExpectedChunks() = runTest {
        oirRule.fake.text.completeStreamReturns("hello world".toTextChunks())

        val result = Oir.text.completeStream("prompt")
            .toList().joinToString("") { it.text }

        assertEquals("hello world", result)
    }
}
```

`OirFake` exposes programmable stubs for every capability. Tests don't need a JibarOS device; the fake replaces the binder adapter in-process.

## Java interop

Every Kotlin coroutine API has a Java-friendly blocking / callback wrapper under `com.oir.java.*`:

```java
import com.oir.java.OirJavaText;

// Blocking — runs on the caller's thread, blocks until done.
String result = OirJavaText.complete(prompt, options);

// Async callback
OirJavaText.completeStream(prompt, options, new TextChunkCallback() {
    @Override public void onChunk(TextChunk chunk) { … }
    @Override public void onComplete(long totalMs)  { … }
    @Override public void onError(Throwable t)      { … }
});
```

## See also

- [`CAPABILITIES.md`](./CAPABILITIES.md) — capability shapes, permissions, defaults
- [`KNOBS.md`](./KNOBS.md) — per-request options + OEM tuning
- [`oir-demo`](https://github.com/Jibar-OS/oir-demo) — reference app
