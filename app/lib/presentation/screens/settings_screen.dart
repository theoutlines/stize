import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/back_to_button.dart';

// Serbian first — the app's home city is Belgrade. `null` (follow the system)
// stays on top: it's the default, not a language. Russian was removed on
// 2026-11-22: the design-system font (Uncut Sans) has no Cyrillic.
const _localeOptions = <String?>[null, 'sr', 'en'];

/// Settings as a full page — kept for the `/settings` route (deep links); the
/// menu opens the same controls as a sheet ([showSettingsSheet]).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const BackToButton(),
        leadingWidth: BackToButton.leadingWidth,
        title: Text(l10n.settingsTitle),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: SettingsPanel(),
      ),
    );
  }
}

/// Opens Settings as a compact sheet over whatever is on screen (the menu's
/// entry point): two controls don't warrant a full-screen page, and the map and
/// any open stop stay where they are underneath.
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.settingsTitle, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              const SettingsPanel(),
            ],
          ),
        ),
      );
    },
  );
}

/// The settings controls: language and theme as segmented controls. No
/// vehicle-mode item by design: the map's layers button is the single control
/// for it (the mode persists via SettingsStore).
class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (err, st) => Center(child: Text(err.toString())),
      data: (settings) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SegmentedSetting<String?>(
            label: l10n.settingsLanguage,
            value: settings.localeCode,
            options: [
              for (final code in _localeOptions)
                (code, code == null ? l10n.settingsAuto : _localeLabel(code)),
            ],
            onChanged: controller.setLocaleCode,
          ),
          const SizedBox(height: 20),
          _SegmentedSetting<ThemeMode>(
            label: l10n.settingsTheme,
            value: settings.themeMode,
            options: [
              (ThemeMode.system, l10n.settingsAuto),
              (ThemeMode.light, l10n.settingsThemeLight),
              (ThemeMode.dark, l10n.settingsThemeDark),
            ],
            onChanged: controller.setThemeMode,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.settingsAutoHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  String _localeLabel(String? code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'sr':
        return 'Srpski';
      default:
        return 'System';
    }
  }
}

/// A labelled row of equal-width segments; the selected one is filled.
class _SegmentedSetting<T> extends StatelessWidget {
  const _SegmentedSetting({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              for (final (option, text) in options)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: option == value,
                    child: Material(
                      color: option == value ? scheme.onSurface : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onChanged(option),
                        child: SizedBox(
                          height: 40,
                          child: Center(
                            child: Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: option == value
                                    ? scheme.surface
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
