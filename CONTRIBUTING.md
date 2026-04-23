# Contributing

Thanks for your interest in JibarOS and the Open Intelligence Runtime (OIR).

## Getting oriented

Start with [`docs/README.md`](https://github.com/jibar-os/docs/blob/main/README.md) — it explains what JibarOS is, what OIR is, and which repo owns what.

Each repo in the `jibar-os` org has a single purpose:

| Repo | Purpose |
|---|---|
| `docs` | Landing page, architecture, OEM guide |
| `manifest` | `repo init` target — points at every other repo |
| `oird` | Native inference daemon (C++) |
| `oir-framework-addons` | Platform service (Java) + AIDL + capabilities.xml |
| `oir-patches` | Small patches to upstream AOSP files |
| `oir-sdk` | Kotlin SDK + AOSP companion |
| `oir-demo` | Mission Control demo app |
| `oir-vendor-models` | Permissive-license model bundle |

## How to contribute

### Small fixes (typos, doc clarifications)

Open a PR directly. One maintainer approval merges.

### Bug fixes

1. File an issue in the affected repo describing the bug + repro steps.
2. Mention the JibarOS/OIR version you hit it on.
3. If you have a fix, open a PR referencing the issue.

### New features

1. File an issue in the relevant repo proposing the feature **before** writing code.
2. Discuss scope with maintainers. Some features may belong in a different repo than you expect, or in an external fork rather than the main runtime.
3. Once scoped, open a PR.

### New capabilities (OIR)

Adding a new capability (e.g. `audio.<new-thing>`) touches `oir-framework-addons` (AIDL + OIRService dispatch), `oird` (native backend), and `oir-sdk` (client API). File one issue in `oir-framework-addons` coordinating the cross-repo change.

## Code standards

- **License:** Apache 2.0 for all new code. Every source file needs a copyright header referencing the Apache 2.0 license.
- **Style:**
  - Java / AIDL — follow AOSP style (4-space indent, K&R braces).
  - Kotlin — follow the [Kotlin style guide](https://kotlinlang.org/docs/coding-conventions.html).
  - C++ — follow Google C++ Style guide as adapted by AOSP (4-space indent, no tabs).
- **Commits:** One logical change per commit. Title line under 70 chars. Explain *why* in the body, not just *what*.

## Testing expectations

### Code with cvd validation path

PRs that touch `oird`, `oir-framework-addons`, or `oir-patches` need validation on a Cuttlefish build. If you don't have a JibarOS build environment, note this in the PR — a maintainer will validate before merge.

### Code without cvd validation path

- `oir-sdk` (Kotlin) — runs a Gradle `check` task; include unit tests where practical.
- `oir-demo` — manual validation; describe what you exercised.
- `docs`, `manifest` — reviewer-only.

## Signing off

Contributions require a `Signed-off-by` line per commit, asserting the [Developer Certificate of Origin](https://developercertificate.org/). `git commit -s` adds it automatically.

## Reporting vulnerabilities

Do **not** open a public issue for security vulnerabilities. See [`SECURITY.md`](./SECURITY.md) for the private reporting channel.

## Code of Conduct

This project follows the [Code of Conduct](./CODE_OF_CONDUCT.md). By participating you agree to uphold it.
