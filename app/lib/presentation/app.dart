import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_config.dart';
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

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
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
