# Security Policy

## Supported Versions

JibarOS follows a rolling-release model. Only the latest tagged release receives security fixes.

| Version | Supported |
|---|---|
| Latest stable tag | ✅ |
| Older tags | ❌ (no backports) |
| `main` branch | ✅ (pre-release; fixes land here first) |

## Reporting a Vulnerability

If you believe you have found a security vulnerability in any JibarOS repository, please **do not** open a public GitHub issue.

Use **GitHub Security Advisories** — open the affected repository, navigate to the **Security** tab, and click **Report a vulnerability**. This keeps the report private until a coordinated fix lands. Maintainers are notified immediately.

Please include:

- A description of the vulnerability and its impact.
- Steps to reproduce (or a proof-of-concept).
- The affected repository, file, and version (commit SHA or tag).
- Any mitigations you have identified.

## What to expect

- **Acknowledgment** within 72 hours of the report.
- **Initial assessment** within one week — we'll confirm the issue, assign a severity, and propose a timeline.
- **Fix + disclosure** — we'll coordinate with you on a disclosure date. Critical issues target a fix within 30 days; high-severity within 60 days; medium/low on a best-effort basis tied to the next release.
- **Credit** — we'll credit you in the release notes unless you prefer to remain anonymous.

## Scope

In scope:

- All code in any `github.com/Jibar-OS/*` repository.
- Runtime behaviour of OIR on a reference Cuttlefish build.
- Inference-time vulnerabilities (e.g. malformed model files crashing `oird`, or AIDL input handling flaws).

Out of scope:

- Vulnerabilities in upstream Android / AOSP — please report those directly to Google's Android Security Team.
- Vulnerabilities in bundled third-party models or their upstream toolchains (llama.cpp, whisper.cpp, ONNX Runtime, Piper). We will help forward where possible, but the upstream project is the authoritative owner.
- Social engineering or phishing reports.

## Non-vulnerabilities

The following are known-and-accepted behaviours, not vulnerabilities:

- `oird` loading any GGUF/ONNX file from `/product/etc/oir/` — the runtime trusts files in that path because the path is read-only system partition. Reports that boil down to "I replaced an installed model file" require root + remount and are not in scope.
- `cmd oir` shell commands running under SHELL_UID bypass rate-limiting by design. See `docs/CLI.md` and `v0.5` rate-limit documentation.
