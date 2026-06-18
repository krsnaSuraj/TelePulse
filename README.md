# TelePulse

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Android](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](https://flutter.dev)
![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter)
[![Telegram](https://img.shields.io/badge/Telegram-MTProto%20Proxy-2AABEE?logo=telegram)](https://telegram.org)

MTProto proxy discovery engine for Android. Fetches, validates, and ranks Telegram proxies across 5 distributed source groups. Bypasses IP-level network restrictions using local `tg://` intents — no web intermediates, no central server.

## Why TelePulse?

Telegram provides proxy *configuration* — you supply a `server:port:secret` and it attempts to connect. TelePulse provides the *supply chain* — automatic discovery, validation, and ranking of working proxies.

| Capability | Telegram Built-in | TelePulse |
|---|---|---|
| Proxy discovery | Manual entry required | Auto-fetches from 7 source endpoints |
| Pre-connection validation | Blind apply | TCP connect (2s timeout, no handshake) |
| Ranking | Chronological | Latency, port-443, source trust, failure feedback |
| Multi-source aggregation | 5 manual slots max | 7 sources + custom URLs |
| Favorites persistence | None | SharedPreferences bookmarking |
| Cache strategy | None | Fresh + stale tiered cache |
| Network-aware | Manual re-check | Auto re-test on connectivity change |
| Concurrent testing | Sequential | 50 parallel sockets, throttled state updates |
| Failure feedback | None | Per-proxy counter penalizes non-working proxies |
| Link sharing | Manual copy | Long-press clipboard copy |

## Quick Start

```bash
git clone https://github.com/krsnaSuraj/TelePulse.git
cd TelePulse
flutter pub get
flutter build apk --debug
flutter install
```

On first launch, the app fetches all sources in parallel, tests every proxy at 50 concurrency, and displays results incrementally as batches complete. Cached proxies appear immediately; fresh results stream in as tests finish.

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
| Framework | Flutter 3.27+ / Dart 3.12 | Single codebase, native ARM64 |
| State | Riverpod 2.6 (StateNotifier) | Zero code-gen, testable, composable |
| HTTP fetch | Dio 5.7 | Retry, timeout, interceptor support |
| Proxy validation | `dart:io` Socket.connect | TCP only — protocol handshakes cause false positives |
| Ranking | Custom score function | Latency score + source trust + port bonus + failure penalty |
| Cache | SharedPreferences | JSON serialization; no SQLite dependency |
| Deep link | `url_launcher` + `tg://` intent | Direct resolution with t.me fallback |
| Monitoring | `connectivity_plus` | Cross-platform offline/online detection |

## Ranking System

Proxies are ranked by a composite score:

- **+100** if TCP-alive with <3 user-reported failures
- **+10** from trusted sources (SoliSpirit, kort0881, Grim1313)
- **+15** if FakeTLS (`ee` prefix), **+5** if obfuscated (`dd` prefix)
- **+8** for port 443 (less likely to be blocked)
- **−50 per user-reported failure** (tapped but Telegram wouldn't connect)
- **Latency bonus**: 50ms→50pts, 100ms→40pts, 300ms→25pts, 500ms→10pts

Proxies with ≥3 failures are excluded from "Fastest Proxies" until they re-test as TCP-alive (which resets the counter). This ensures that only proxies the user has actually *used successfully* stay at the top.

## Auto-Update

Update checks against the **GitHub Releases API** (`/repos/krsnaSuraj/TelePulse/releases/latest`). A "Check for Updates" tile in Settings triggers the flow:

1. Fetch latest release tag from GitHub (10s timeout)
2. Compare with current version from `PackageInfo`
3. Release notes + download dialog if newer
4. APK download URL resolved from release assets
5. Cached for 1 hour; skip-version persistence via SharedPreferences

To publish an update: push a version tag (`git tag v1.0.1 && git push --tags`), then upload the APK to a new GitHub Release manually. Users see the dialog on next check.

## Performance Budget

| Phase | Latency | Notes |
|---|---|---|
| Cache load (tested) | ~50ms | From SharedPreferences |
| Full fetch | 5-10s | Parallel HTTP requests |
| Full test (200 proxies) | ~8s | 2s connect ÷ 50 concurrency |
| Incremental update | per 3 batches (~6s) | Throttled state merge |
| App cold start to ready | ~1s | Cache-first rendering on launch |

## License

MIT — see [LICENSE](LICENSE)
