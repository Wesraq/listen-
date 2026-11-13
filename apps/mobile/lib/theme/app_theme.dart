import 'package:flutter/material.dart';

class ListenColors {
  static const ink = Color(0xFF1A1F2C);
  static const coral = Color(0xFFE07A5F);
  static const sand = Color(0xFFF7F3EE);
  static const mist = Color(0xFFE8EEF2);
  static const leaf = Color(0xFF2F6F5E);
}

ThemeData buildListenTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ListenColors.leaf,
      primary: ListenColors.leaf,
      secondary: ListenColors.coral,
      surface: ListenColors.sand,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: ListenColors.sand,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: ListenColors.ink,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: ListenColors.ink,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: ListenColors.ink,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: ListenColors.sand,
      foregroundColor: ListenColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ListenColors.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: ListenColors.leaf.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? ListenColors.leaf : ListenColors.ink.withValues(alpha: 0.55),
        );
      }),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: ListenColors.leaf,
      disabledColor: ListenColors.mist,
      checkmarkColor: Colors.white,
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: ListenColors.ink,
      ),
      secondaryLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      side: BorderSide(color: ListenColors.ink.withValues(alpha: 0.18)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
  );
}
