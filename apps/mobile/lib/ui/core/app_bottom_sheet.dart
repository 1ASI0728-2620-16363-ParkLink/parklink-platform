import 'package:flutter/material.dart';

import 'app_theme.dart';

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: appWhite,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
    ),
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Duration(milliseconds: 240),
            reverseDuration: Duration(milliseconds: 180),
          ),
    builder: (context) => Theme(
      data: buildAppSheetTheme(),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Builder(builder: builder),
        ),
      ),
    ),
  );
}

ThemeData buildAppSheetTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: appLime,
        brightness: Brightness.light,
      ).copyWith(
        primary: appLime,
        onPrimary: appBlack,
        primaryContainer: appLime,
        onPrimaryContainer: appBlack,
        secondary: appLime,
        onSecondary: appBlack,
        secondaryContainer: appLime,
        onSecondaryContainer: appBlack,
        tertiary: appLime,
        onTertiary: appBlack,
        error: appBlack,
        onError: appWhite,
        errorContainer: const Color(0xFFE8E8E8),
        onErrorContainer: appBlack,
        surface: appWhite,
        onSurface: appBlack,
      );

  return ThemeData.light(useMaterial3: true).copyWith(
    textTheme: ThemeData.light().textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: appBlack,
      displayColor: appBlack,
    ),
    colorScheme: colorScheme,
    canvasColor: appWhite,
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(appWhite),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF3F3F3),
      labelStyle: const TextStyle(color: Color(0xFF626262)),
      prefixIconColor: const Color(0xFF626262),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE2E2E2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: appLime, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: appLime,
        foregroundColor: appBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: appBlack,
        side: const BorderSide(color: Color(0xFFDDDDDD)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: appBlack,
        minimumSize: const Size(48, 48),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: appBlack,
        minimumSize: const Size(48, 48),
      ),
    ),
  );
}
