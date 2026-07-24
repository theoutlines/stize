import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final feedMeta = ref.watch(feedMetaProvider).valueOrNull;
    final routeDataLabel = _routeDataLabel(context, l10n, feedMeta?.feedStartDate);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aboutTitle),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/settings')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(l10n.appTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(l10n.aboutDisclaimer, style: theme.textTheme.bodyMedium),
          ),
          // Reference-data freshness. Only shown once /gtfs-meta resolves with a
          // date; if it's unavailable the row is simply absent (silent fallback).
          if (routeDataLabel != null) ...[
            const SizedBox(height: 16),
            Text(
              routeDataLabel,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }

  /// `Route data: <Month Year>`, month localized to the active locale. Returns
  /// null when there's no date to show, so the caller omits the row entirely.
  String? _routeDataLabel(BuildContext context, AppLocalizations l10n, DateTime? date) {
    if (date == null) return null;
    final locale = Localizations.localeOf(context).toString();
    String formatted;
    try {
      formatted = DateFormat.yMMMM(locale).format(date);
    } catch (_) {
      // Locale data not available — fall back to a plain, unambiguous form.
      formatted = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    }
    return l10n.aboutRouteData(formatted);
  }
}
