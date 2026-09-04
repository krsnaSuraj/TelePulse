import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color surface = Color(0xFF0B0C0E);
  static const Color surfaceCard = Color(0xFF141518);
  static const Color surfaceElevated = Color(0xFF1C1E22);
  static const Color surfaceBorder = Color(0xFF26282D);
  static const Color surfaceOverlay = Color(0xFF202227);

  static const Color signal = Color(0xFFE8A33D);
  static const Color signalSoft = Color(0xFFC98A2E);
  static const Color signalDim = Color(0x33E8A33D);

  static const Color textPrimary = Color(0xFFEDEEF0);
  static const Color textSecondary = Color(0xFFA7ABB2);
  static const Color textMuted = Color(0xFF8A9099);
  static const Color textFaint = Color(0xFF9AA0A8);

  static const Color alive = Color(0xFF3FCF8E);
  static const Color aliveDim = Color(0x1F3FCF8E);
  static const Color dead = Color(0xFFE5484D);
  static const Color deadDim = Color(0x1FE5484D);
  static const Color warn = Color(0xFFD97706);
  static const Color warnDim = Color(0x1FD97706);
  static const Color slowAlive = Color(0xFFF0A04B);
  static const Color favorite = Color(0xFFF2C14E);

  static const Color hairline = Color(0x14FFFFFF);
  static const Color hairlineStrong = Color(0x26FFFFFF);

  static const Color onSignalInk = Color(0xFF1A1305);
}

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Roboto';
  static const double radius = 10.0;

  static ThemeData get dark {
    final colorScheme = ColorScheme.dark(
      primary: AppColors.signal,
      secondary: AppColors.signal,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      outline: AppColors.surfaceBorder,
      error: AppColors.dead,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleSpacing: 0,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: 0.2,
        ),
        iconTheme: const IconThemeData(
          color: AppColors.textSecondary,
          size: 22,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.hairline, width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        minLeadingWidth: 24,
        iconColor: AppColors.textSecondary,
        titleTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0D0E10),
        indicatorColor: AppColors.signalDim,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        height: 68,
        elevation: 0,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused) ||
              states.contains(WidgetState.hovered)) {
            return AppColors.signal.withValues(alpha: 0.16);
          }
          return null;
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: fontFamily,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? AppColors.signal : AppColors.textMuted,
            letterSpacing: 0.2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: isSelected ? AppColors.signal : AppColors.textMuted,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceOverlay,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 13.5,
          color: AppColors.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.hairlineStrong, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.surfaceBorder,
        thickness: 1,
        space: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        hintStyle: const TextStyle(
          fontFamily: fontFamily,
          color: AppColors.textMuted,
          fontSize: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(
            color: AppColors.surfaceBorder,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(
            color: AppColors.surfaceBorder,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppColors.signal, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.signal,
          foregroundColor: AppColors.onSignalInk,
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: 0.2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.signal,
          side: const BorderSide(color: AppColors.surfaceBorder, width: 1),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle>(
            TextStyle(
              fontFamily: fontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: AppColors.surfaceBorder, width: 1),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        selectedIcon: const Icon(Icons.check_rounded, size: 16),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.hairlineStrong, width: 1),
        ),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 13.5,
          color: AppColors.textPrimary,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(AppColors.textSecondary),
          splashFactory: InkRipple.splashFactory,
          minimumSize: WidgetStateProperty.all(const Size(48, 48)),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)) {
              return AppColors.signal.withValues(alpha: 0.16);
            }
            return null;
          }),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.hairlineStrong, width: 1),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13.5,
          color: AppColors.textSecondary,
          height: 1.5,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.signal,
        linearTrackColor: AppColors.surfaceBorder,
      ),
    );
  }
}
