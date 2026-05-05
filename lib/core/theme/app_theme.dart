import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // ── Light color tokens ───────────────────────────────────────────
  static const Color colorBg         = Color(0xFFF4F5F7);
  static const Color colorSurface    = Color(0xFFFFFFFF);
  static const Color colorSurfaceAlt = Color(0xFFFBFBFD);
  static const Color colorNavy       = Color(0xFF0B1B2B);
  static const Color colorNavySoft   = Color(0xFF16314B);
  static const Color colorMint       = Color(0xFF4FD1B6);
  static const Color colorMintDeep   = Color(0xFF2BAF95);
  static const Color colorMintTint   = Color(0xFFE7F8F4);
  static const Color colorCoral      = Color(0xFFFF7A6B);
  static const Color colorCoralDeep  = Color(0xFFE85A4C);
  static const Color colorCoralTint  = Color(0xFFFFECE8);
  static const Color colorCatDiet    = Color(0xFFFFB072);
  static const Color colorCatSleep   = Color(0xFF7C9CF0);
  static const Color colorText       = Color(0xFF0B1B2B);
  static const Color colorTextMid    = Color(0xFF3C4A5C);
  static const Color colorTextSub    = Color(0xFF6B7785);
  static const Color colorTextDim    = Color(0xFF9AA3AF);
  static const Color colorHairBorder = Color(0x140B1B2B);

  // ── Dark color tokens ────────────────────────────────────────────
  static const Color colorBgDark         = Color(0xFF0E141B);
  static const Color colorSurfaceDark    = Color(0xFF1A232E);
  static const Color colorSurfaceAltDark = Color(0xFF22303C);
  static const Color colorMintDark       = Color(0xFF5DDCC1);
  static const Color colorMintTintDark   = Color(0xFF143129);
  static const Color colorCoralDark      = Color(0xFFFF9082);
  static const Color colorCoralTintDark  = Color(0xFF3A1D1A);
  static const Color colorTextDark       = Color(0xFFE8EEF4);
  static const Color colorTextMidDark    = Color(0xFFB0BAC6);
  static const Color colorTextSubDark    = Color(0xFF8792A1);
  static const Color colorTextDimDark    = Color(0xFF6B7785);
  static const Color colorHairBorderDark = Color(0x22FFFFFF);

  // ── Diet category tints (점심/간식 전용) ──────────────────────
  static const Color colorLunchTint      = Color(0xFFEEF5FF);
  static const Color colorLunchTintDark  = Color(0xFF1B2A3F);
  static const Color colorSnackTint      = Color(0xFFFFF3E8);
  static const Color colorSnackTintDark  = Color(0xFF3A2D1E);

  // ── Category semantic colors (summary/diet 차트 라벨) ─────────
  static const Color colorCatDietDark    = Color(0xFFE8965C);
  static const Color colorCatSleepDark   = Color(0xFF6584D4);

  // ── Warning palette (설정 spreadsheet_status_card 등) ─────────
  static const Color colorWarnBg         = Color(0xFFFFD9A8);
  static const Color colorWarnBgDark     = Color(0xFF3A2D1E);
  static const Color colorWarnFg         = Color(0xFF8C6A3A);
  static const Color colorWarnFgDark     = Color(0xFFE8A860);

  // ── Macro nutrition labels (탄/단/지 라벨 색) ─────────────────
  // carbs 는 기존 catDiet (주황) 재사용. protein/fat 는 신규 토큰.
  static const Color colorMacroProteinFg     = Color(0xFF4A8AC9);
  static const Color colorMacroProteinFgDark = Color(0xFF6BA4DD);
  static const Color colorMacroFatFg         = Color(0xFFC4A52A);
  static const Color colorMacroFatFgDark     = Color(0xFFD9C152);

  // ── Brightness-aware helpers ─────────────────────────────────
  static Color catDiet(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? colorCatDietDark : colorCatDiet;
  static Color catSleep(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? colorCatSleepDark : colorCatSleep;
  static Color lunchTint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? colorLunchTintDark : colorLunchTint;
  static Color snackTint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? colorSnackTintDark : colorSnackTint;
  static Color warnBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? colorWarnBgDark : colorWarnBg;
  static Color warnFg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? colorWarnFgDark : colorWarnFg;
  static Color macroCarbsFg(BuildContext context) => catDiet(context);
  static Color macroProteinFg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? colorMacroProteinFgDark
          : colorMacroProteinFg;
  static Color macroFatFg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? colorMacroFatFgDark
          : colorMacroFatFg;

  // ── Liquid Glass surface helpers (iOS 26 glass specular 시뮬레이션) ──
  // 의도적 brand: white 반사광은 유리 표면 효과라 cs 토큰으로 대체 불가.
  // 위젯에서 Colors.white 직접 참조를 막기 위해 헬퍼로 격리 (conventions.md §2).
  static Color glassSpecular(BuildContext context) =>
      Colors.white.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.60);
  static Color glassInnerGlow(BuildContext context) =>
      Colors.white.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.05 : 0.10);
  static Color glassPillFill(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return cs.onSurface.withOpacity(isDark ? 0.14 : 0.08);
  }
  static Color glassPillBorder(BuildContext context) =>
      Colors.white.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.08 : 0.35);
  static Color glassPillInner(BuildContext context) =>
      Colors.white.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.06 : 0.18);

  static ThemeData get lightTheme {
    const cs = ColorScheme.light(
      primary:              colorNavy,
      onPrimary:            Colors.white,
      primaryContainer:     colorMintTint,
      onPrimaryContainer:   colorNavy,
      secondary:            colorMint,
      onSecondary:          Colors.white,
      secondaryContainer:   colorMintTint,
      onSecondaryContainer: colorNavy,
      tertiary:             colorCoral,
      onTertiary:           Colors.white,
      tertiaryContainer:    colorCoralTint,
      onTertiaryContainer:  colorNavy,
      error:                colorCoral,
      surface:              colorSurface,
      onSurface:            colorText,
      onSurfaceVariant:     colorTextSub,
      outline:              colorTextDim,
      outlineVariant:       colorHairBorder,
      surfaceContainerHighest: Color(0xFFEEF0F2),
      surfaceContainerLowest:  colorSurfaceAlt,
      inverseSurface:       colorNavy,
      onInverseSurface:     Colors.white,
    );
    return _buildTheme(
      colorScheme: cs,
      scaffoldBg: colorBg,
      appBarFg: colorNavy,
      cardSurface: colorSurface,
      cardBorder: colorHairBorder,
      cardShadow: const Color(0x0F0B1B2B),
      inputFill: colorBg,
      inputBorder: colorHairBorder,
      inputFocused: colorMint,
      filledBtnBg: colorNavy,
      filledBtnFg: Colors.white,
      chipBg: colorBg,
      chipSelected: colorMintTint,
      chipBorder: colorHairBorder,
      chipFg: colorText,
      segmentBg: colorBg,
      segmentSelectedBg: colorMintTint,
      segmentSelectedFg: colorMintDeep,
      segmentUnselectedFg: colorTextSub,
      segmentBorder: colorHairBorder,
      bodySmallColor: colorTextSub,
      labelSmallColor: colorTextDim,
      systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
    );
  }

  static ThemeData get darkTheme {
    const cs = ColorScheme.dark(
      primary:              colorMintDark,
      onPrimary:            colorBgDark,
      primaryContainer:     colorMintTintDark,
      onPrimaryContainer:   colorMintDark,
      secondary:            colorMintDark,
      onSecondary:          colorBgDark,
      secondaryContainer:   colorMintTintDark,
      onSecondaryContainer: colorMintDark,
      tertiary:             colorCoralDark,
      onTertiary:           colorBgDark,
      tertiaryContainer:    colorCoralTintDark,
      onTertiaryContainer:  colorCoralDark,
      error:                colorCoralDark,
      surface:              colorSurfaceDark,
      onSurface:            colorTextDark,
      onSurfaceVariant:     colorTextSubDark,
      outline:              colorTextDimDark,
      outlineVariant:       colorHairBorderDark,
      surfaceContainerHighest: Color(0xFF2C3A48),
      surfaceContainerLowest:  colorSurfaceAltDark,
      inverseSurface:       colorSurface,
      onInverseSurface:     colorNavy,
    );
    return _buildTheme(
      colorScheme: cs,
      scaffoldBg: colorBgDark,
      appBarFg: colorTextDark,
      cardSurface: colorSurfaceDark,
      cardBorder: colorHairBorderDark,
      cardShadow: Colors.black,
      inputFill: colorSurfaceAltDark,
      inputBorder: colorHairBorderDark,
      inputFocused: colorMintDark,
      filledBtnBg: colorMintDark,
      filledBtnFg: colorBgDark,
      chipBg: colorSurfaceAltDark,
      chipSelected: colorMintTintDark,
      chipBorder: colorHairBorderDark,
      chipFg: colorTextDark,
      segmentBg: colorSurfaceAltDark,
      segmentSelectedBg: colorMintTintDark,
      segmentSelectedFg: colorMintDark,
      segmentUnselectedFg: colorTextSubDark,
      segmentBorder: colorHairBorderDark,
      bodySmallColor: colorTextSubDark,
      labelSmallColor: colorTextDimDark,
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBg,
    required Color appBarFg,
    required Color cardSurface,
    required Color cardBorder,
    required Color cardShadow,
    required Color inputFill,
    required Color inputBorder,
    required Color inputFocused,
    required Color filledBtnBg,
    required Color filledBtnFg,
    required Color chipBg,
    required Color chipSelected,
    required Color chipBorder,
    required Color chipFg,
    required Color segmentBg,
    required Color segmentSelectedBg,
    required Color segmentSelectedFg,
    required Color segmentUnselectedFg,
    required Color segmentBorder,
    required Color bodySmallColor,
    required Color labelSmallColor,
    required SystemUiOverlayStyle systemOverlayStyle,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      fontFamily: 'Pretendard',
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: appBarFg,
        systemOverlayStyle: systemOverlayStyle,
        titleTextStyle: TextStyle(
          fontFamily: 'Pretendard',
          color: appBarFg,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardSurface,
        shadowColor: cardShadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: cardBorder, width: 1),
        ),
      ),
      textTheme: TextTheme(
        headlineLarge:  const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w700, letterSpacing: -0.8),
        headlineMedium: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w700, letterSpacing: -0.8),
        headlineSmall:  const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, letterSpacing: -0.8),
        titleLarge:     const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, letterSpacing: -0.8),
        titleMedium:    const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, letterSpacing: -0.4),
        titleSmall:     const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600),
        bodyLarge:      const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w400),
        bodyMedium:     const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w400),
        bodySmall:      TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w400, color: bodySmallColor),
        labelLarge:     const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600),
        labelMedium:    const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w500),
        labelSmall:     TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w500, color: labelSmallColor),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: inputFocused, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: filledBtnBg,
          foregroundColor: filledBtnFg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: chipBg,
        selectedColor: chipSelected,
        labelStyle: TextStyle(
          fontFamily: 'Pretendard',
          fontWeight: FontWeight.w500,
          color: chipFg,
        ),
        side: BorderSide(color: chipBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return segmentSelectedBg;
            return segmentBg;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return segmentSelectedFg;
            return segmentUnselectedFg;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: segmentBorder)),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        ),
      ),
    );
  }
}
