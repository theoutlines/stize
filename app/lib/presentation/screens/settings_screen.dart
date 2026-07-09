import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';

const _refreshIntervalOptions = [15, 30, 60];
const _localeOptions = <String?>[null, 'en', 'ru', 'sr'];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (err, st) => Center(child: Text(err.toString())),
        data: (settings) => ListView(
          children: [
            ListTile(title: Text(l10n.settingsLanguage)),
            for (final code in _localeOptions)
              RadioListTile<String?>.adaptive(
                title: Text(_localeLabel(code)),
                value: code,
                groupValue: settings.localeCode,
                onChanged: (value) => controller.setLocaleCode(value),
              ),
            const Divider(),
            ListTile(title: Text(l10n.settingsTheme)),
            RadioListTile<ThemeMode>.adaptive(
              title: Text(l10n.settingsThemeSystem),
              value: ThemeMode.system,
              groupValue: settings.themeMode,
              onChanged: (value) => controller.setThemeMode(value!),
            ),
            RadioListTile<ThemeMode>.adaptive(
              title: Text(l10n.settingsThemeLight),
              value: ThemeMode.light,
              groupValue: settings.themeMode,
              onChanged: (value) => controller.setThemeMode(value!),
            ),
            RadioListTile<ThemeMode>.adaptive(
              title: Text(l10n.settingsThemeDark),
              value: ThemeMode.dark,
              groupValue: settings.themeMode,
              onChanged: (value) => controller.setThemeMode(value!),
            ),
            const Divider(),
            ListTile(title: Text(l10n.settingsRefreshInterval)),
            for (final seconds in _refreshIntervalOptions)
              RadioListTile<int>.adaptive(
                title: Text(l10n.settingsRefreshIntervalSeconds(seconds)),
                value: seconds,
                groupValue: settings.refreshIntervalSeconds,
                onChanged: (value) => controller.setRefreshIntervalSeconds(value!),
              ),
          ],
        ),
      ),
    );
  }

  String _localeLabel(String? code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'ru':
        return 'Русский';
      case 'sr':
        return 'Srpski';
      default:
        return 'System';
    }
  }
}
