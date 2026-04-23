# Models

Every OIR capability has a backing model. This doc covers: what ships in the reference Cuttlefish bundle, where models live on-device, how to sideload during development, and how OEMs bake different models for a shipped product.

## Reference bundle (Cuttlefish baseline)

The [`oir-vendor-models`](https://github.com/Jibar-OS/oir-vendor-models) repo is a Git-LFS bundle of permissively-licensed models that install to `/product/etc/oir/` via `prebuilt_etc` modules.

| File | Capability served | License | Size |
|---|---|---|---|
| `qwen2.5-0.5b-instruct-q4_k_m.gguf` | `text.complete`, `text.translate` | Apache 2.0 | ~470 MB |
| `all-MiniLM-L6-v2.Q8_0.gguf` | `text.embed` | Apache 2.0 | ~24 MB |
| `whisper-tiny-en.Q5.bin` | `audio.transcribe` | MIT | ~31 MB |
| `siglip-base-patch16-224.onnx` | `vision.embed` | Apache 2.0 | ~372 MB |
| `voice-sample.wav` | OirDemo `audio.transcribe` demo input | CC0 | ~720 KB |

The Cuttlefish reference build (`device_google_cuttlefish`) ships with these five in `PRODUCT_PACKAGES`:

```make
PRODUCT_PACKAGES += \
    oir_default_model \
    oir_minilm_model \
    oir_whisper_tiny_en_model \
    oir_siglip_model \
    oir_voice_sample_wav
```

## Deliberately not bundled

These capabilities are declared in `capabilities.xml` but ship **without a platform default** because no permissively-licensed universal default exists:

| Capability | Why not bundled |
|---|---|
| `vision.describe` | VLMs are typically 500 MB–5 GB. Size/quality tradeoff is device-dependent (SmolVLM-500M for thin devices, LLaVA-7B for flagships). |
| `vision.detect` | RT-DETR ships as the permissive default. YOLO family is AGPL — OEMs who accept the AGPL obligations can swap via `capability_tuning.vision.detect.default_model`. |
| `audio.synthesize` | Piper voice + `.phonemes.json` G2P sidecar is **locale-specific**. No universal voice default. |
| `text.classify` / `text.rerank` | Classifier heads are task-specific. No universal default. |
| `vision.ocr` | Needs a det+rec ONNX pair plus a vocab sidecar — language-specific. |

OEMs bake their choice for each — see [OEM guide](#oem-bake-in-guide) below.

## On-device layout

```
/product/etc/oir/                                ← platform model bundle (read-only, signed)
    qwen2.5-0.5b-instruct-q4_k_m.gguf
    all-MiniLM-L6-v2.Q8_0.gguf
    whisper-tiny-en.Q5.bin
    siglip-base-patch16-224.onnx
    voice-sample.wav
    <vendor-supplied VLM, piper voice, etc.>
    <model>.phonemes.json                        ← Piper G2P sidecar (required per voice)
    <model>.labels.txt                           ← vision.detect class sidecar (optional; falls back to COCO-80)

/system_ext/etc/oir/
    capabilities.xml                             ← platform capability declarations

/vendor/etc/oir/
    *.xml                                        ← OEM capability fragments + oir_config.xml

/data/local/oir/                                 ← dev-override path (not on shipped devices)
    <gguf or onnx>                               ← worker checks here FIRST — sideload without rebuild
```

### Dev sideload (no rebuild)

During development, `adb push` a model to `/data/local/oir/` and `oird` picks it up ahead of the baked-in default. This is how we validated v0.6.9 — pushed SmolVLM + mmproj for `vision.describe` without rebuilding the super.img.

```bash
adb root && adb remount
adb push my-model.gguf /data/local/oir/my-model.gguf
# Edit /vendor/etc/oir/oir_config.xml (or patch capabilities.xml) to point
# the target capability at /data/local/oir/my-model.gguf.
adb shell pkill system_server           # force OIRService to re-read capabilities
```

## OEM bake-in guide

To ship a JibarOS-based product with your own models per capability:

### 1. Pick a model per capability

Decide which model serves each capability on your target device. Considerations:

- **Memory footprint** — device RAM gates how many concurrent capabilities can resident. A 2 GB VLM blocks everything else.
- **Throughput** — 7B-class models on CPU are 1–2 tok/s on mid-range devices. Plan for latency.
- **License** — OIR ships only permissive defaults. OEMs choose freely but own license compliance.

### 2. Add the model to your vendor repo

If you're using the reference `oir-vendor-models` repo:

```bash
git clone https://github.com/Jibar-OS/oir-vendor-models
cd oir-vendor-models
git lfs install
git lfs track "*.gguf" "*.onnx" "*.bin"
cp /path/to/my-vlm.gguf models/
# Edit Android.bp to declare a prebuilt_etc module:
```

```soong
prebuilt_etc {
    name: "oir_my_vlm",
    src: "models/my-vlm.gguf",
    sub_dir: "oir",
    product_specific: true,
    filename_from_src: true,
}
```

OR create your own OEM vendor-models repo following the same pattern.

### 3. Wire into PRODUCT_PACKAGES

In your device tree's `device.mk`:

```make
PRODUCT_PACKAGES += oir_my_vlm
```

### 4. Point the capability at your model

Drop `/vendor/etc/oir/oir_config.xml` on the built image:

```xml
<oir_config>
    <capability_tuning>
        <capability name="vision.describe">
            <default_model>/product/etc/oir/my-vlm-mmproj.gguf|/product/etc/oir/my-vlm-llm.gguf</default_model>
        </capability>
    </capability_tuning>
</oir_config>
```

Or, for capabilities that DO have a platform default you want to override, ship a vendor capability fragment at `/vendor/etc/oir/my-oem.xml`. Note that OEM fragments cannot shadow platform-declared capabilities — only add new ones or supply missing defaults via the tuning-knob escape hatch above.

### 5. Validate

`cmd oir dumpsys capabilities` should report every target capability as `[RUNNABLE]` after your changes. Fire a test request:

```bash
cmd oir describe /product/etc/oir/bus.jpg "What do you see?"
```

See a streamed English description of `bus.jpg`.

## Licenses

All first-party JibarOS code is Apache 2.0. Model licenses vary — see the [`NOTICE`](https://github.com/Jibar-OS/oir-vendor-models/blob/main/NOTICE) file in `oir-vendor-models` for per-file attribution. Non-permissive models (LLaVA research-only, YOLO AGPL, GPT-variant weights) are NOT bundled in the reference build to keep `oir-vendor-models` redistributable under Apache 2.0.

## See also

- [`CAPABILITIES.md`](./CAPABILITIES.md) — which shape/backend each capability uses
- [`KNOBS.md`](./KNOBS.md) — `oir_config.xml` syntax + per-capability tunables
- [`BUILD.md`](./BUILD.md) — building JibarOS from a clean clone
