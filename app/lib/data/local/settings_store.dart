import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/vehicle_map_mode.dart';

/// null locale means "follow system", matching the app-wide system-by-default
/// rule for both theme and language.
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.localeCode,
    required this.vehicleMapMode,
  });

  final ThemeMode themeMode;
  final String? localeCode; // 'en' | 'ru' | 'sr' | null (system)
  // null = never chosen → the mode falls back to the flag-driven default
  // (see resolveVehicleMapMode).
  final VehicleMapMode? vehicleMapMode;

  static const defaults = AppSettings(
    themeMode: ThemeMode.system,
    localeCode: null,
    vehicleMapMode: null,
  );

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? Function()? localeCode,
    VehicleMapMode? Function()? vehicleMapMode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      localeCode: localeCode != null ? localeCode() : this.localeCode,
      vehicleMapMode:
          vehicleMapMode != null ? vehicleMapMode() : this.vehicleMapMode,
    );
  }
}

class SettingsStore {
  static const _themeKey = 'settings_theme_mode';
  static const _localeKey = 'settings_locale_code';
  static const _vehicleMapModeKey = 'settings_vehicle_map_mode';
  // Removed setting (F9): the poll interval is now a fixed 30s constant. Kept
  // only to clean any previously-stored value out on load.
  static const _legacyRefreshKey = 'settings_refresh_interval_seconds';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Migrate away the dropped refresh-interval preference.
    if (prefs.containsKey(_legacyRefreshKey)) {
      await prefs.remove(_legacyRefreshKey);
    }
    final themeString = prefs.getString(_themeKey);
    final theme = ThemeMode.values.firstWhere(
      (m) => m.name == themeString,
      orElse: () => ThemeMode.system,
    );
    final modeString = prefs.getString(_vehicleMapModeKey);
    return AppSettings(
      themeMode: theme,
      localeCode: prefs.getString(_localeKey),
      // An unknown/absent value reads as "never chosen", not as a mode.
      vehicleMapMode: VehicleMapMode.values
          .where((m) => m.name == modeString)
          .firstOrNull,
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

  Future<void> saveVehicleMapMode(VehicleMapMode? mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode == null) {
      await prefs.remove(_vehicleMapModeKey);
    } else {
      await prefs.setString(_vehicleMapModeKey, mode.name);
    }
  }
}
