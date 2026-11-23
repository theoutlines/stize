import 'package:stize/presentation/widgets/page_app_bar.dart';
import 'package:stize/core/design/components/stize_page_column.dart';
import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';

import '../../core/design/components/stize_segmented.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/context_slot.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../../core/design/stize_icons.dart';

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

    return StizePageColumn(
      child: Scaffold(
        appBar: pageAppBar(context, l10n.settingsTitle),
        body: const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SettingsPanel(),
        ),
      ),
    );
  }
}

/// Opens Settings as a compact sheet over whatever is on screen (the menu's
/// entry point): two controls don't warrant a full-screen page, and the map and
/// any open stop stay where they are underneath.
Future<void> showSettingsSheet(BuildContext context) {
  // Desktop: a compact centred card (owner, 2026-11-23); a bottom sheet
  // stretched across a wide window reads as a stray strip.
  if (isWideLayout(MediaQuery.sizeOf(context).width)) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => PointerInterceptor(
        child: ((dialogContext) {
          final l10n = AppLocalizations.of(dialogContext);
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.settingsTitle,
                            style: StizeText.of(dialogContext).section,
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            dialogContext,
                          ).closeButtonTooltip,
                          icon: const Icon(StizeIcons.close, size: 20),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SettingsPanel(),
                    ),
                  ],
                ),
              ),
            ),
          );
        })(ctx),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => PointerInterceptor(
      child: ((sheetContext) {
        final l10n = AppLocalizations.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.settingsTitle,
                  style: StizeText.of(sheetContext).section,
                ),
                const SizedBox(height: 16),
                const SettingsPanel(),
              ],
            ),
          ),
        );
      })(ctx),
    ),
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
          StizeSegmented<String?>(
            label: l10n.settingsLanguage,
            value: settings.localeCode,
            options: [
              for (final code in _localeOptions)
                (code, code == null ? l10n.settingsAuto : _localeLabel(code)),
            ],
            onChanged: controller.setLocaleCode,
          ),
          const SizedBox(height: 20),
          StizeSegmented<ThemeMode>(
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
            style: StizeText.of(context).caption.copyWith(
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
