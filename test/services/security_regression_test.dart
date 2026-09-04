import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telepulse/services/host_filter.dart';
import 'package:telepulse/services/proxy_fetcher_service.dart';
import 'package:telepulse/services/proxy_parser.dart';
import 'package:telepulse/services/update_service.dart';

// Public IP literal bypasses real DNS (host_filter.dart:94-97).
const _publicLitUrl = 'https://8.8.8.8/list.txt';

Dio _dioResolving(
  Response<ResponseBody> Function(RequestOptions o) fn, {
  void Function()? onReq,
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        onReq?.call();
        h.resolve(fn(o));
      },
    ),
  );
  return dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F1 proxy_fetcher_service.dart:76 null ResponseBody must not throw', () {
    test('200 with null data returns []', () async {
      final dio = _dioResolving(
        (o) => Response<ResponseBody>(
          requestOptions: o,
          statusCode: 200,
          data: null,
        ),
      );
      final f = ProxyFetcherService(dio: dio);
      // Pre-fix: throws Null check operator at :76, caught -> [] but masks bug.
      // Post-fix: explicit null guard returns null -> [] cleanly.
      expect(await f.fetchOnlyCustomUrl(_publicLitUrl), isEmpty);
    });
  });

  group('F2/F6 DNS + literal filter (host_filter.dart)', () {
    test('loopback literals blocked, public allowed', () async {
      expect(HostFilter.isDisallowedLiteral('127.0.0.1'), isTrue);
      expect(HostFilter.isDisallowedLiteral('10.0.0.5'), isTrue);
      expect(HostFilter.isDisallowedLiteral('169.254.169.254'), isTrue);
      expect(HostFilter.isDisallowedLiteral('8.8.8.8'), isFalse);
      expect(await HostFilter.resolveAllowed('127.0.0.1'), isNull);
      expect(await HostFilter.resolveAllowed('8.8.8.8'), isNotNull);
    });
  });

  group('F3/F4 redirect (proxy_fetcher_service.dart:38,60-65)', () {
    test('self-loop terminates within 4 requests', () async {
      var n = 0;
      final dio = _dioResolving(
        (o) => Response<ResponseBody>(
          requestOptions: o,
          statusCode: 302,
          headers: Headers.fromMap({
            'location': ['https://8.8.8.8/loop'],
          }),
          data: null,
        ),
        onReq: () => n++,
      );
      final f = ProxyFetcherService(dio: dio);
      expect(await f.fetchOnlyCustomUrl('https://8.8.8.8/loop'), isEmpty);
      expect(n, lessThanOrEqualTo(4));
    });

    test('https->http downgrade never issues 2nd request', () async {
      var n = 0;
      final dio = _dioResolving(
        (o) => Response<ResponseBody>(
          requestOptions: o,
          statusCode: 302,
          headers: Headers.fromMap({
            'location': ['http://8.8.8.8/evil'],
          }),
          data: null,
        ),
        onReq: () => n++,
      );
      expect(
        await ProxyFetcherService(
          dio: dio,
        ).fetchOnlyCustomUrl('https://8.8.8.8/start'),
        isEmpty,
      );
      expect(n, 1, reason: 'scheme!=https aborts at :47-48');
    });
  });

  group('F9 update_service.dart:163-178 untrusted APK (FIXED)', () {
    test(
      'attacker raw.githubusercontent APK must be rejected',
      () {
        // FIXED via isTrustedArtifactUrl: raw attacker path rejected.
        final got = UpdateService.trustedApkAssetUrl([
          {
            'name': 'app-release.apk',
            'browser_download_url':
                'https://raw.githubusercontent.com/attacker/malware/main/app-release.apk',
          },
        ]);
        expect(
          got,
          isNull,
          reason: 'POST-FIX: attacker raw URL must be null',
        );
      },
    );

    test('legit own-repo APK accepted', () {
      expect(
        UpdateService.trustedApkAssetUrl([
          {
            'name': 'app-release.apk',
            'browser_download_url':
                'https://github.com/krsnaSuraj/TelePulse/releases/download/v0.2.0/telepulse.apk',
          },
        ]),
        isNotNull,
      );
    });

    test('poisoned prefs with attacker raw URL rejected (FIXED)', () async {
      SharedPreferences.setMockInitialValues({
        'tp_v2_update_payload': jsonEncode({
          'latestVersion': '9.9.9',
          'downloadUrl':
              'https://raw.githubusercontent.com/attacker/m/main/app-release.apk',
          'releaseNotes': 'x',
          'releaseDate': '',
        }),
        'tp_v2_update_checked_at': DateTime.now().toIso8601String(),
      });
      // FIXED via isTrustedArtifactUrl in loadCachedUpdate.
      final cached = await UpdateService().loadCachedUpdate();
      expect(
        cached,
        isNull,
        reason: 'POST-FIX: poisoned cache must be null',
      );
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });
  });

  group('F7 proxy_parser.dart:164-173 userinfo smuggling (FIXED)', () {
    test('userinfo URLs rejected', () {
      expect(
        ProxyParser.isValidCustomSourceUrl(
          'https://user:pass@8.8.8.8/list.txt',
        ),
        isFalse,
        reason: 'POST-FIX: userinfo must be rejected',
      );
      expect(ProxyParser.isValidCustomSourceUrl(_publicLitUrl), isTrue);
    });
  });
}
