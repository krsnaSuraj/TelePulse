class AppConstants {
  AppConstants._();

  static const sourceConnectTimeout = Duration(seconds: 10);
  static const sourceReceiveTimeout = Duration(seconds: 15);
  static const sourceEnvelopeTimeout = Duration(seconds: 40);
  static const maxSourceBodyBytes = 2 * 1024 * 1024;

  static const tcpConnectTimeout = Duration(milliseconds: 2000);
  static const perProxyEnvelopeTimeout = Duration(seconds: 4);
  static const mobileVerifyCap = 10;

  static const concurrencyWifi = 50;
  static const concurrencyMobile = 12;
  static const openStaggerBase = Duration(milliseconds: 8);
  static const openStaggerJitterMaxMs = 12;

  static const fetchedCacheTtl = Duration(hours: 1);
  static const testedCacheTtl = Duration(hours: 24);
  static const maxCachedTestedEntries = 2000;

  static const connectivityStableWindow = Duration(seconds: 5);
  static const cacheWriteDebounce = Duration(milliseconds: 400);

  static const minSecretLength = 16;
  static const maxSecretLength = 128;
  static const maxHostLength = 253;
  static const maxFailuresBeforeExclusion = 3;
  static const maxTrackedFailures = 10;
}
