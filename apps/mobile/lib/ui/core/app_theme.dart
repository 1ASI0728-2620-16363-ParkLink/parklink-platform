import 'package:flutter/material.dart';

const appBlack = Color(0xFF000000);
const appSurface = Color(0xFF141414);
const appSurfaceSoft = Color(0xFF1C1C1C);
const appLime = Color(0xFF00C8D7);
const appWhite = Color(0xFFFFFFFF);

/// Rojo de emergencia: el SOS no debe confundirse con una acción normal.
const appEmergency = Color(0xFFD62828);
const appDashboardCard = Color(0xFF181818);
const appDashboardCardSoft = Color(0xFF222222);
const appDashboardBorder = Color(0xFF303030);
const appDashboardTextMuted = Color(0xFFA5A5A0);
const appDashboardTextSubtle = Color(0xFF737370);
const appDashboardLight = Color(0xFFE4E4DF);
const appDashboardTrack = Color(0xFF383838);

ThemeData buildAppTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: appLime,
        brightness: Brightness.dark,
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
        error: const Color(0xFFFFB4AB),
        onError: appBlack,
        errorContainer: const Color(0xFF3B1616),
        onErrorContainer: const Color(0xFFFFDAD6),
        surface: appSurface,
        onSurface: appWhite,
        surfaceContainerHighest: appSurfaceSoft,
        outline: const Color(0xFF303030),
      );

  return ThemeData(
    fontFamily: 'Inter',
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: appBlack,
    textTheme: ThemeData.dark().textTheme
        .apply(fontFamily: 'Inter')
        .copyWith(
          headlineMedium: const TextStyle(
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
          titleLarge: const TextStyle(
            fontSize: 22,
            height: 1.25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          titleMedium: const TextStyle(
            fontSize: 17,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: const TextStyle(fontSize: 16, height: 1.5),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
          bodySmall: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: appDashboardTextMuted,
          ),
        ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: appSurfaceSoft,
      contentTextStyle: const TextStyle(color: appWhite),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: appWhite,
    ),
    cardTheme: CardThemeData(
      color: appSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      labelStyle: const TextStyle(color: Color(0xFFB8B8B8)),
      floatingLabelStyle: const TextStyle(
        color: appLime,
        fontWeight: FontWeight.w800,
        backgroundColor: appSurface,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Color(0xFF303030)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Color(0xFF303030)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: appLime,
        foregroundColor: appBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: appLime,
        foregroundColor: appBlack,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: appWhite,
        backgroundColor: appSurface,
        side: const BorderSide(color: Color(0xFF303030)),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: appWhite,
      indicatorColor: appLime,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
      ),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: states.contains(WidgetState.selected)
              ? appBlack
              : const Color(0xFF6B7280),
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 38,
          color: states.contains(WidgetState.selected)
              ? appBlack
              : const Color(0xFF6B7280),
        ),
      ),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(color: appWhite, fontWeight: FontWeight.w700),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(appSurfaceSoft),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
  );
}
