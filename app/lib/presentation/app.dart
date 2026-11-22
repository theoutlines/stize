import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_config.dart';
import '../core/design/stize_theme.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import 'providers/providers.dart';
import 'router.dart';
import 'widgets/staging_badge.dart';

class StiglaApp extends ConsumerWidget {
  const StiglaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    // The Stiže design system is behind the remote `ds_stize` flag; OFF keeps
    // the previous Material theme (killswitch).
    final ds = ref.watch(dsStizeEnabledProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: ds ? StizeTheme.light() : AppTheme.light,
      darkTheme: ds ? StizeTheme.dark() : AppTheme.dark,
      themeMode: settings?.themeMode ?? ThemeMode.system,
      locale: settings?.localeCode != null ? Locale(settings!.localeCode!) : null,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: appRouter,
      // Overlay a STAGING marker on the test build only.
      builder: isStaging
          ? (context, child) => Stack(
              children: [?child, const StagingBadge()],
            )
          : null,
    );
  }
}
