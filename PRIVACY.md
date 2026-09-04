# Privacy Policy

TelePulse is built for people whose connectivity is restricted. The privacy bar is therefore absolute:

## What TelePulse collects

**Nothing.**

- No analytics, crash reporting, or telemetry SDKs exist in the binary.
- No accounts, no registration, no identifiers.
- Android permissions: `INTERNET` (declared) + `ACCESS_NETWORK_STATE` (merged
  in from the `connectivity_plus` dependency to detect Wi-Fi vs. mobile and
  connection loss). `ACCESS_NETWORK_STATE` is read-only network status; it
  does not grant location or device identifiers.

## What leaves your device

| Request | Destination | When |
|---|---|---|
| Fetch proxy lists | `raw.githubusercontent.com`, `cdn.jsdelivr.net` (the URLs are listed in `lib/data/proxy_sources.dart`) | app launch, pull-to-refresh, reconnect |
| Check for updates | `api.github.com` (repo releases; APK downloads may come from `github.com` / `objects.githubusercontent.com`) | manual check only |
| Open a proxy | Telegram (`tg://…`) or `t.me` link | when you tap a proxy |

Your ISP can see that your device contacts these hosts — that is true of any internet use and is unavoidable. Requests carry a generic `TelePulse/<version>` user agent.

## Who can see what (recipients)

- **Proxy-list hosts** (`raw.githubusercontent.com`, `cdn.jsdelivr.net`): see
  your IP address and user agent when the app fetches lists.
- **Update host** (`api.github.com`, plus `github.com` /
  `objects.githubusercontent.com` for APK downloads): sees your IP address
  and user agent on manual update checks only.
- **Proxy operators** (the MTProto relays you tap to use): see your IP
  address and that you use Telegram once you connect through them. They can
  observe connection metadata. Only use proxies from sources you trust.
- **Your ISP / network observer**: can see the hosts above that your device
  contacts (it cannot see the content of HTTPS fetches).

TelePulse itself receives nothing — there is no developer server.

## What stays on your device

- Cached proxy results, favorites, and custom source URLs (SharedPreferences; excluded from Google cloud backup and device transfer via `allowBackup=false` + data-extraction rules).
- Nothing is written to shared storage.

### Retention

| Data | Key(s) | Lifetime |
|---|---|---|
| Tested proxy results | `tp_v2_tested_proxies` / `tp_v2_tested_at` | Fresh for 24h (`testedCacheTtl`); stale fallback kept up to 7 days (`staleGrace`), then ignored |
| Fetched (untested) proxy lists | `tp_v2_fetched_proxies` / `tp_v2_fetched_at` | Fresh for 1h (`fetchedCacheTtl`) |
| Update check result | `tp_v2_update_payload` / `tp_v2_update_checked_at` / `tp_v2_update_uptodate_version` / `tp_v2_update_skip_version` | 1h |
| Favorites, custom sources, Wi-Fi-only + auto-scan toggles | `tp_v2_favorites`, `tp_v2_custom_sources`, `tp_v2_wifi_only`, `tp_v2_autoscan` | Until you delete them |

Entries older than the stale grace are treated as absent (not rendered).

## Deletion

- **All local data:** Android Settings → Apps → TelePulse → Storage → Clear
  data wipes everything, or call `ProxyCacheService.deleteAllData()` (removes
  every `tp_v2_*` key listed above, including caches, favorites, custom
  sources, toggles, and update state).
- **Caches only:** `ProxyCacheService.clear()` removes the fetched/tested
  caches and leaves favorites, custom sources, and settings untouched.
- No account or server-side copy exists to delete — the developer has nothing
  to erase on your behalf.

## Clipboard

If Telegram is not installed, the `tg://proxy?…` link is copied to your clipboard so you can paste it manually. Your operating system may surface clipboard contents to other apps or cloud-sync features you have enabled; clear it if that concerns you.

## Third-party content

Proxy lists come from independent third-party repositories. TelePulse validates their *format* and reachability but cannot vouch for the operators of the proxies they publish.

## Changes

Material changes to this policy will be noted in the release notes.
