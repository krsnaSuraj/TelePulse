import 'package:flutter/services.dart';

class AppHaptics {
  AppHaptics._();

  static void light() => _guard(HapticFeedback.lightImpact);
  static void selection() => _guard(HapticFeedback.selectionClick);

  static void success() {
    _guard(HapticFeedback.mediumImpact);
    Future.delayed(const Duration(milliseconds: 60), () {
      _guard(HapticFeedback.lightImpact);
    });
  }

  static void error() {
    _guard(HapticFeedback.heavyImpact);
    Future.delayed(const Duration(milliseconds: 100), () {
      _guard(HapticFeedback.heavyImpact);
    });
  }

  static void _guard(void Function() feedback) {
    try {
      feedback();
    } catch (_) {}
  }
}
