# manifest — JibarOS repo manifest

`repo init` target. Pulls JibarOS + upstream AOSP into a buildable tree.

## Usage

```bash
mkdir jibar-os && cd jibar-os
repo init -u https://github.com/jibar-os/manifest -b main
repo sync -c -j8
```

This checks out upstream AOSP + every JibarOS repo into the right tree locations.

## What's here

- `default.xml` — main manifest (upstream AOSP `main` + JibarOS overlay)
- `snapshots/` — version-pinned manifests for reproducible builds (`v0.6.9.xml`, etc.)

## See also

[`github.com/jibar-os/docs`](https://github.com/jibar-os/docs) — JibarOS landing page, architecture, repo guide.

## Migration status

🚧 Code migration in progress. See the JibarOS project prep branch in `rufolangus/OpenIntelligenceRuntime` for the canonical source ahead of this repo landing.
