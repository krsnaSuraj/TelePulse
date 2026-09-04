import 'package:package_info_plus/package_info_plus.dart';

class AppMeta {
  AppMeta._();

  static String version = '0.1.0';
  static String buildNumber = '1';
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
    } catch (_) {
      // Keep compile-time defaults when the platform plugin is unavailable.
    }
    _initialized = true;
  }

  static String get userAgent => 'TelePulse/$version';
}
