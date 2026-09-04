import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/services/update_service.dart';

void main() {
  group('normalizeVersion', () {
    test('strips v prefix, prerelease and build metadata', () {
      expect(UpdateService.normalizeVersion('v1.2.3'), '1.2.3');
      expect(UpdateService.normalizeVersion('1.2.3-beta.1'), '1.2.3');
      expect(UpdateService.normalizeVersion('v1.0.2+5'), '1.0.2');
      expect(UpdateService.normalizeVersion('V2.0.0-rc1+build9'),
          '2.0.0');
    });
  });

  group('compareVersions', () {
    test('orders numerically across components', () {
      expect(UpdateService.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0.1', '1.0.0'), 1);
      expect(UpdateService.compareVersions('1.10.0', '1.9.9'), 1);
      expect(UpdateService.compareVersions('2.0.0', '1.99.99'), 1);
      expect(UpdateService.compareVersions('0.9', '0.9.0'), 0);
      expect(UpdateService.compareVersions('1.0.0', '1.0.1'), -1);
    });

    test('ignores prerelease/build suffixes via normalization contract',
        () {
      final a = UpdateService.normalizeVersion('1.1.0-beta');
      final b = UpdateService.normalizeVersion('1.1.0');
      expect(UpdateService.compareVersions(a, b), 0);
    });

    test('degrades garbage components to zero safely', () {
      expect(UpdateService.compareVersions('x.y.z', '0.0.0'), 0);
      expect(
          UpdateService.compareVersions('1.x.3', '1.0.4'), lessThan(0));
    });
  });

  group('isTrustedAssetHost', () {
    test('accepts GitHub-owned HTTPS hosts regardless of path', () {
      expect(
        UpdateService.isTrustedAssetHost(
            'https://github.com/krsnaSuraj/TelePulse/releases/download/v1.0.0/app.apk'),
        isTrue,
      );
      expect(
        UpdateService.isTrustedAssetHost(
            'https://objects.githubusercontent.com/9f8e7d6c5b4a/asset.apk?z=1'),
        isTrue,
        reason:
            'release asset CDN paths carry no repo name; trust comes from the signed API response',
      );
      expect(
        UpdateService.isTrustedAssetHost(
            'https://raw.githubusercontent.com/u/r/main/f.txt'),
        isTrue,
      );
    });

    test('rejects non-HTTPS and lookalike hosts', () {
      expect(
        UpdateService.isTrustedAssetHost(
            'http://github.com/krsnaSuraj/TelePulse/releases/latest'),
        isFalse,
      );
      expect(
        UpdateService.isTrustedAssetHost('https://evil.com/apk'),
        isFalse,
      );
      expect(
        UpdateService.isTrustedAssetHost('https://github.com.evil.com/a'),
        isFalse,
      );
      expect(
        UpdateService.isTrustedAssetHost('not-a-url'),
        isFalse,
      );
    });
  });

  group('isTrustedDownloadUrl', () {
    test('requires the own-repo path on trusted hosts', () {
      expect(
        UpdateService.isTrustedDownloadUrl(
            'https://github.com/krsnaSuraj/TelePulse/releases/download/v1.0.0/app.apk'),
        isTrue,
      );
      expect(
        UpdateService.isTrustedDownloadUrl(
            'https://github.com/krsnaSuraj/TelePulse/releases/tag/v0.2.0'),
        isTrue,
      );
    });

    test('rejects non-HTTPS, lookalikes and foreign repos', () {
      expect(
        UpdateService.isTrustedDownloadUrl(
            'http://github.com/krsnaSuraj/TelePulse/releases/latest'),
        isFalse,
      );
      expect(
        UpdateService.isTrustedDownloadUrl('https://evil.com/apk'),
        isFalse,
      );
      expect(
        UpdateService.isTrustedDownloadUrl('https://github.com.evil.com/a'),
        isFalse,
      );
      expect(
        UpdateService.isTrustedDownloadUrl(
            'https://github.com/attacker/TelePulse/releases/download/v9/app.apk'),
        isFalse,
        reason: 'same repo name under a different owner must not pass',
      );
      expect(
        UpdateService.isTrustedDownloadUrl(
            'https://github.com/krsnaSuraj/OtherApp/releases/download/v1/a.apk'),
        isFalse,
        reason: 'different repo under the same owner must not pass',
      );
      expect(
        UpdateService.isTrustedDownloadUrl('not-a-url'),
        isFalse,
      );
    });
  });

  group('trustedApkAssetUrl', () {
    test('picks first non-debug APK on a trusted host', () {
      final url = UpdateService.trustedApkAssetUrl([
        {'name': 'app-debug.apk', 'browser_download_url': 'https://github.com/krsnaSuraj/TelePulse/releases/download/v1/app-debug.apk'},
        {'name': 'app-release.apk', 'browser_download_url': 'https://github.com/krsnaSuraj/TelePulse/releases/download/v1/app-release.apk'},
      ]);
      expect(url, 'https://github.com/krsnaSuraj/TelePulse/releases/download/v1/app-release.apk');
    });

    test('skips untrusted hosts even for APK assets', () {
      final url = UpdateService.trustedApkAssetUrl([
        {'name': 'app-release.apk', 'browser_download_url': 'https://evilcdn.io/app-release.apk'},
      ]);
      expect(url, isNull);
    });

    test('returns null for malformed asset lists', () {
      expect(UpdateService.trustedApkAssetUrl(null), isNull);
      expect(UpdateService.trustedApkAssetUrl('nope'), isNull);
      expect(
        UpdateService.trustedApkAssetUrl([
          'string-instead-of-map',
          {'name': 42},
        ]),
        isNull,
      );
    });
  });

  group('parseRelease', () {
    final baseRelease = <String, dynamic>{
      'tag_name': 'v0.2.0',
      'html_url': 'https://github.com/krsnaSuraj/TelePulse/releases/tag/v0.2.0',
      'assets': [
        {
          'name': 'telepulse.apk',
          'browser_download_url':
              'https://github.com/krsnaSuraj/TelePulse/releases/download/v0.2.0/telepulse.apk',
        }
      ],
      'body': 'Bug fixes',
      'published_at': '2026-01-01T00:00:00Z',
    };

    test('builds UpdateInfo for newer release', () {
      final info = UpdateService.parseRelease(baseRelease,
          currentVersion: '0.1.0');
      expect(info, isNotNull);
      expect(info!.latestVersion, '0.2.0');
      expect(info.downloadUrl, contains('telepulse.apk'));
      expect(info.releaseNotes, 'Bug fixes');
    });

    test('returns null when release is not newer', () {
      expect(
        UpdateService.parseRelease(baseRelease, currentVersion: '0.2.0'),
        isNull,
      );
      expect(
        UpdateService.parseRelease(baseRelease, currentVersion: '1.0.0'),
        isNull,
      );
    });

    test('falls back to trusted html_url when no APK asset', () {
      final info = UpdateService.parseRelease({
        ...baseRelease,
        'assets': <Object>[],
      }, currentVersion: '0.1.0');
      expect(info!.downloadUrl, baseRelease['html_url']);
    });

    test('rejects untrusted html_url fallback', () {
      final info = UpdateService.parseRelease({
        ...baseRelease,
        'assets': <Object>[],
        'html_url': 'https://evil.example/download',
      }, currentVersion: '0.1.0');
      expect(info!.downloadUrl,
          'https://github.com/krsnaSuraj/TelePulse/releases/latest');
    });

    test('handles missing tag gracefully', () {
      expect(
        UpdateService.parseRelease({}, currentVersion: '0.1.0'),
        isNull,
      );
    });
  });
}
