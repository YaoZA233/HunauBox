import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeColorProvider = StateNotifierProvider<ThemeColorNotifier, Color>((
  ref,
) {
  return ThemeColorNotifier();
});

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return ThemeModeNotifier();
});

class ThemeColorNotifier extends StateNotifier<Color> {
  static const String _colorKey = 'theme_color';
  // A calm fern green gives the app a campus-and-field identity without
  // pushing every surface toward a bright accent color.
  static const Color defaultColor = Color(0xFF486A5A);

  ThemeColorNotifier() : super(defaultColor) {
    _loadThemeColor();
  }

  Future<void> _loadThemeColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_colorKey);
    if (colorValue != null) {
      // Migrate the former default so an existing install receives the new
      // palette while still preserving any other custom color choice.
      state = colorValue == 0xFF1A73E8 ? defaultColor : Color(colorValue);
    }
  }

  Future<void> updateThemeColor(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorKey, color.value);
  }
}

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const String _modeKey = 'theme_mode';

  ThemeModeNotifier() : super(ThemeMode.system) {
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_modeKey);
    state = switch (savedMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }
}
