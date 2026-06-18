# TelePulse

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Android](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](https://flutter.dev)
![Flutter](https://img.shields.io/badge/Flutter-3.12+-02569B?logo=flutter)
[![Telegram](https://img.shields.io/badge/Telegram-MTProto%20Proxy-2AABEE?logo=telegram)](https://telegram.org)

MTProto proxy discovery engine for Android. Fetches, validates, and ranks Telegram proxies across 5 distributed source groups. Bypasses IP-level network restrictions using local `tg://` intents — no web intermediates, no central server.

## Why TelePulse?

Telegram provides proxy *configuration* — you supply a `server:port:secret` and it attempts to connect. TelePulse provides the *supply chain* — automatic discovery, validation, and ranking of working proxies.

| Capability | Telegram Built-in | TelePulse |
|---|---|---|
| Proxy discovery | Manual entry required | Auto-fetches from 5 source groups |
| Pre-connection validation | Blind apply | TCP connect + protocol handshake |
| Ranking | Chronological | Latency, port-443, source trust |
| Multi-source aggregation | 5 manual slots max | 5 sources + custom URLs |
| Favorites persistence | None | SharedPreferences bookmarking |
| Cache strategy | None | Fresh + stale tiered cache |
| Network-aware | Manual re-check | Auto re-test on connectivity change |
| Concurrent testing | Sequential | 50 parallel sockets, throttled state updates |
| Link sharing | Manual copy | Long-press clipboard copy |

## Quick Start

```bash
git clone https://github.com/krsnaSuraj/TelePulse.git
cd TelePulse
flutter pub get
flutter build apk --debug
flutter install
```

On first launch, the app fetches all sources in parallel, tests every proxy at 50 concurrency, and displays results incrementally as batches complete.

## Proxy Sources

| Group | Sources | Type | Endpoint |
|---|---|---|---|
| SoliSpirit | GitHub raw | Primary | SoliSpirit/mtproto |
| kort0881 | all + EU + RU | Primary | kort0881/proxy\_\*.txt |
| Grim1313 | Fork mirror | Primary | Grim1313/all\_proxies.txt |
| iwh3n / ALIILAPRO | Scrapers | Secondary | GitHub raw |
| Fallbacks | CDN mirror + HTML | Mirror | jsDelivr + HTML parser |

Sources auto-disable after 3 consecutive failures with a 30-minute recovery window.

## Technical Stack

| Component | Choice | Rationale |
|---|---|---|
| Framework | Flutter 3.12+ / Dart 3.12 | Single codebase, native ARM64 |
| State | Riverpod 2.6 (StateNotifier) | Zero code-gen, testable, composable |
| HTTP fetch | Dio 5.9 | Retry, timeout, interceptor support |
| Proxy test | `dart:io` Socket | Direct TCP; no HTTP overhead, offline-capable |
| Cache | SharedPreferences | JSON serialization; no SQLite dependency |
| Deep link | `url_launcher` + `tg://` intent | Direct resolution |
| Monitoring | `connectivity_plus` | Cross-platform offline/online detection |

## Auto-Update

Update checks against the **GitHub Releases API** (`/repos/krsnaSuraj/TelePulse/releases/latest`). A Check for Updates tile in Settings triggers the flow:

1. Fetch latest release tag from GitHub (10s timeout)
2. Compare with current version from `PackageInfo`
3. Release notes + download dialog if newer
4. APK download URL resolved from release assets
5. Cached for 1 hour; skip-version persistence via SharedPreferences

To publish an update: push a version tag (`git tag v1.0.1 && git push --tags`). GitHub Actions builds the APK, creates a Release, and uploads it automatically. Users see the dialog on next check.

## Performance Budget

| Phase | Latency | Notes |
|---|---|---|
| Cache load (tested) | ~50ms | From SharedPreferences |
| Full fetch | 5-10s | Parallel HTTP requests |
| Full test (200 proxies) | ~14s | 2s connect + 2s handshake ÷ 50 concurrency |
| Incremental update | per 3 batches (~6s) | Throttled state merge |
| App cold start to ready | ~1s | Cache-first rendering |

## Security

Release APKs are built with **Dart obfuscation** (`--obfuscate --split-debug-info`). All class/function names are renamed in the compiled binary, making reverse engineering significantly harder. Source code remains MIT open source on GitHub. Debug symbols (for crash trace deobfuscation) are stored as a separate artifact with 7-day retention in CI builds.

## License

MIT — see [LICENSE](LICENSE)
