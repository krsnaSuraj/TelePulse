# Contributing to TelePulse

Thanks for helping! This guide gets you from clone to green CI in five minutes.

## Prerequisites

- Flutter **3.44+** / Dart 3.12 (`flutter --version`)
- JDK 17 for the Android toolchain
- No signing setup required — see below

## Getting started

```bash
git clone https://github.com/krsnaSuraj/TelePulse.git
cd TelePulse
flutter pub get
flutter run            # debug build signs itself with the debug key
```

You do **not** need `android/key.properties` for local builds — a missing keystore falls back to the debug key with an explicit warning. **CI is fail-closed:** release builds on CI throw instead of signing with the debug key.

## Before opening a PR

```bash
flutter analyze        # must report: No issues found
flutter test           # must pass (all suites)
```

CI runs both plus a debug APK build on every push/PR.

## Project conventions

- **No doc drift**: if you change behaviour, update README/ARCHITECTURE in the same PR. Architecture claims must match code — this is enforced culturally via review.
- **Tests for behaviour changes**: bug fixes need a regression test that fails without the fix (see `test/providers/proxy_list_notifier_test.dart › REGRESSION` for the pattern).
- Pure logic lives in `services/` as static/testable functions where possible; widgets stay thin.
- Keep the dependency list minimal; every new package needs justification in the PR description (supply-chain surface matters for this audience).
- Comments: explain *why*, not *what*.

## Commit style

`area: imperative summary` — e.g.

```
tester: stagger socket opens to reduce scan signature
parser: reject numeric dotted hosts shorter than IPv4
docs: align ranking table with ranker implementation
```

## Release process (maintainer)

1. Update `pubspec.yaml` version + GitHub Release notes.
2. Tag `vX.Y.Z` and push tags.
3. CI builds the artifact; attach the signed APK to the GitHub Release (release job uses secrets: `KEYSTORE_BASE64`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`).

## Reporting bugs

Open an issue with: device/Android version, steps, expected vs actual, and whether a specific proxy/source triggers it. Security issues → use GitHub's private vulnerability reporting (Security tab → Report a vulnerability), never a public issue.
