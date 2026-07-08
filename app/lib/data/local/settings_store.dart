import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// null locale means "follow system", matching the app-wide system-by-default
/// rule for both theme and language.
class AppSettings {
  const AppSettings({required this.themeMode, required this.localeCode, required this.refreshIntervalSeconds});

  final ThemeMode themeMode;
  final String? localeCode; // 'en' | 'ru' | 'sr' | null (system)
  final int refreshIntervalSeconds;

  static const defaults = AppSettings(themeMode: ThemeMode.system, localeCode: null, refreshIntervalSeconds: 30);

  AppSettings copyWith({ThemeMode? themeMode, String? Function()? localeCode, int? refreshIntervalSeconds}) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      localeCode: localeCode != null ? localeCode() : this.localeCode,
      refreshIntervalSeconds: refreshIntervalSeconds ?? this.refreshIntervalSeconds,
    );
  }
}

class SettingsStore {
  static const _themeKey = 'settings_theme_mode';
  static const _localeKey = 'settings_locale_code';
  static const _refreshKey = 'settings_refresh_interval_seconds';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString(_themeKey);
    final theme = ThemeMode.values.firstWhere(
      (m) => m.name == themeString,
      orElse: () => ThemeMode.system,
    );
    return AppSettings(
      themeMode: theme,
      localeCode: prefs.getString(_localeKey),
      refreshIntervalSeconds: prefs.getInt(_refreshKey) ?? AppSettings.defaults.refreshIntervalSeconds,
    );
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  Future<void> saveLocaleCode(String? code) async {
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_localeKey);
    } else {
      await prefs.setString(_localeKey, code);
    }
  }

  Future<void> saveRefreshIntervalSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_refreshKey, seconds);
  }
}
