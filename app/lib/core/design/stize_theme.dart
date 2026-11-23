import 'package:flutter/material.dart';

import 'stize_tokens.dart';

export 'stize_tokens.dart';

/// Motion tokens of the Stiže design system (the transitions.dev scale on the
/// 4px grid, see the design system README). Not part of the generated tokens:
/// the design-system format has no motion family.
abstract final class StizeMotion {
  static const Duration stagger = Duration(milliseconds: 40);
  static const Duration micro = Duration(milliseconds: 80);
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration textSwap = Duration(milliseconds: 200);
  static const Duration fast = Duration(milliseconds: 250);
  static const Duration medium = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration verySlow = Duration(milliseconds: 500);

  /// For anything that moves or resizes.
  static const Curve smoothOut = Cubic(0.22, 1, 0.36, 1);

  /// For fades and swaps.
  static const Curve inOut = Curves.easeInOut;
}

/// ThemeData built from the Stiže design-system tokens.
///
/// Rules that live here so screens don't have to repeat them:
/// - The accent is never a focus ring or a default button colour: the main
///   action is `ink` on `onInk` (Button secondary). The accent marks the answer
///   of a screen (the first live ETA) and is applied explicitly by that widget.
/// - Only weights 400 and 500 in the text theme; 600 exists solely as
///   [StizeType.lineNumber] for line numbers in vertical lists.
/// - The only theme since 2026-11-22 (the `ds_stize` flag and the old Material theme were removed).
abstract final class StizeTheme {
  static ThemeData dark() => _build(StizeColors.dark, Brightness.dark);
  static ThemeData light() => _build(StizeColors.light, Brightness.light);

  static ThemeData _build(StizeColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      // Material "primary" drives many defaults (switches, progress, selection).
      // It is ink, not the accent: the accent is reserved for the answer.
      primary: c.ink,
      onPrimary: c.onInk,
      secondary: c.accent,
      onSecondary: c.onAccent,
      tertiary: c.accent,
      onTertiary: c.onAccent,
      error: c.place,
      onError: c.onTransit,
      surface: c.bg,
      onSurface: c.ink,
      onSurfaceVariant: c.ink60,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.sheet,
      surfaceContainer: c.card,
      surfaceContainerHigh: c.card,
      surfaceContainerHighest: c.raised,
      // `outline` is what legacy widgets use for secondary text and icons
      // (empty states, captions), so it must stay legible: ink50, not the
      // hairline. Hairlines/dividers use `outlineVariant` (and set c.line
      // explicitly in their component themes).
      outline: c.ink50,
      outlineVariant: c.line,
      shadow: Colors.black,
      scrim: c.scrim,
      inverseSurface: c.ink,
      onInverseSurface: c.onInk,
    );

    TextStyle ink(TextStyle s, [Color? color]) =>
        s.copyWith(color: color ?? c.ink);

    final textTheme = TextTheme(
      displayLarge: ink(StizeType.etaHero),
      displayMedium: ink(StizeType.bigNumber),
      displaySmall: ink(StizeType.heroTitle),
      headlineLarge: ink(StizeType.heroTitle),
      headlineMedium: ink(StizeType.h1),
      headlineSmall: ink(StizeType.date),
      titleLarge: ink(StizeType.section),
      titleMedium: ink(StizeType.label),
      titleSmall: ink(StizeType.control),
      bodyLarge: ink(StizeType.body),
      bodyMedium: ink(StizeType.body),
      bodySmall: ink(StizeType.caption, c.ink60),
      labelLarge: ink(StizeType.label),
      labelMedium: ink(StizeType.control),
      labelSmall: ink(StizeType.note, c.ink50),
    );

    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(StizeRadius.radiusControl),
      ),
    );
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(StizeRadius.radiusButton)),
    );
    final focusRing = BorderSide(color: c.ink, width: 2);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: StizeFonts.sans,
      textTheme: textTheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      dividerColor: c.line,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: ink(StizeType.section),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(
          horizontal: StizeSpace.space4,
          vertical: StizeSpace.space1,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(StizeRadius.radiusCard),
          ),
        ),
      ),
      // Button secondary: the screen's main action.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.ink,
          foregroundColor: c.onInk,
          minimumSize: const Size(0, StizeSize.buttonH),
          padding: const EdgeInsets.symmetric(horizontal: StizeSpace.space6),
          shape: buttonShape,
          textStyle: StizeType.label,
          elevation: 0,
        ),
      ),
      // Button tertiary: everything else.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          backgroundColor: c.fill06,
          foregroundColor: c.ink80,
          minimumSize: const Size(0, StizeSize.buttonSmallH),
          padding: const EdgeInsets.symmetric(horizontal: StizeSpace.space4),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(StizeRadius.radiusMd),
            ),
          ),
          textStyle: StizeType.label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink80,
          backgroundColor: c.fill06,
          side: BorderSide.none,
          minimumSize: const Size(0, StizeSize.buttonH),
          shape: buttonShape,
          textStyle: StizeType.label,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.ink,
          foregroundColor: c.onInk,
          elevation: 0,
          minimumSize: const Size(0, StizeSize.buttonH),
          shape: buttonShape,
          textStyle: StizeType.label,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.ink,
          minimumSize: const Size(
            StizeSize.buttonSmallH,
            StizeSize.buttonSmallH,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(StizeRadius.radiusMd),
            ),
          ),
        ),
      ),
      iconTheme: IconThemeData(color: c.ink, size: 24),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.fill05,
        isDense: true,
        constraints: const BoxConstraints(minHeight: StizeSize.controlH),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: StizeSpace.space3,
          vertical: StizeSpace.space2 + 2,
        ),
        hintStyle: StizeType.body.copyWith(color: c.ink50),
        labelStyle: StizeType.control.copyWith(color: c.ink60),
        floatingLabelBehavior: FloatingLabelBehavior.never,
        border: const OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(
            Radius.circular(StizeRadius.radiusControl),
          ),
        ),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(
            Radius.circular(StizeRadius.radiusControl),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: focusRing,
          borderRadius: const BorderRadius.all(
            Radius.circular(StizeRadius.radiusControl),
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: c.accent, width: 2),
          borderRadius: const BorderRadius.all(
            Radius.circular(StizeRadius.radiusControl),
          ),
        ),
        counterStyle: StizeType.caption.copyWith(color: c.ink50),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.ink,
        selectionColor: c.fill24,
        selectionHandleColor: c.ink,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.fill07,
        selectedColor: c.ink,
        disabledColor: c.fill05,
        labelStyle: StizeType.label.copyWith(color: c.ink),
        secondaryLabelStyle: StizeType.label.copyWith(color: c.onInk),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: StizeSpace.space2),
        showCheckmark: false,
        checkmarkColor: c.onInk,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(0, StizeSize.controlH),
          ),
          shape: const WidgetStatePropertyAll(controlShape),
          side: const WidgetStatePropertyAll(BorderSide.none),
          textStyle: const WidgetStatePropertyAll(StizeType.control),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.fill14 : c.fill05,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.ink : c.ink60,
          ),
        ),
        selectedIcon: const SizedBox.shrink(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onInk : c.ink,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.ink : c.fill10,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.ink : c.ink60,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.ink : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(c.onInk),
        side: BorderSide(color: c.ink60, width: 2),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(StizeRadius.radiusXs / 2),
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.fill16,
        inactiveTrackColor: c.fill05,
        thumbColor: c.ink,
        overlayColor: c.fill08,
        valueIndicatorColor: c.raised,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.ink,
        linearTrackColor: c.fill10,
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.ink60,
        textColor: c.ink,
        titleTextStyle: StizeType.label.copyWith(color: c.ink),
        subtitleTextStyle: StizeType.caption.copyWith(color: c.ink60),
        minTileHeight: StizeSize.controlH,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: StizeSpace.space4,
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.sheet,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.sheet,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(StizeRadius.radiusHero),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: StizeType.section.copyWith(color: c.ink),
        contentTextStyle: StizeType.body.copyWith(color: c.ink85),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(StizeRadius.radiusCard),
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.raised,
        contentTextStyle: StizeType.body.copyWith(color: c.ink),
        actionTextColor: c.ink,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(StizeRadius.radiusControl),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: const BorderRadius.all(
            Radius.circular(StizeRadius.radiusSm),
          ),
        ),
        textStyle: StizeType.caption.copyWith(color: c.ink),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: StizeType.body.copyWith(color: c.ink),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(StizeRadius.radiusControl),
          ),
        ),
      ),
    );
  }
}
