import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/drawer_footer.dart';
import '../../core/design/stize_icons.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final feedMeta = ref.watch(feedMetaProvider).valueOrNull;
    final routeDataLabel = _routeDataLabel(
      context,
      l10n,
      feedMeta?.feedStartDate,
    );
    final version = ref.watch(appVersionProvider).valueOrNull;

    return Scaffold(
      // Plain back arrow + left-aligned title (owner, 2026-11-23): the wide
      // "back to stop" slot pushed the centred title off to the right, and the
      // map keeps the open stop as a level anyway.
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(StizeIcons.back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        centerTitle: false,
        titleSpacing: 4,
        title: Text(l10n.aboutTitle),
      ),
      body: ListView(
        // One 16px left edge for every block, like the map's levels.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l10n.aboutDisclaimer,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          // Reference-data freshness. Only shown once /gtfs-meta resolves with a
          // date; if it's unavailable the row is simply absent (silent fallback).
          // Open-data attribution (the licence requires naming the source).
          const SizedBox(height: 16),
          Text(
            l10n.aboutDataSource,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (routeDataLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              routeDataLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
          // Licences and privacy live here, as full-height rows: in the menu
          // they were small adjacent links, too easy to mis-tap on a phone.
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minLeadingWidth: 24,
            horizontalTitleGap: 12,
            leading: const Icon(StizeIcons.document),
            title: Text(l10n.drawerLicenses),
            trailing: const Icon(StizeIcons.chevronRight),
            onTap: () => openLicensesPage(context, l10n, version),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minLeadingWidth: 24,
            horizontalTitleGap: 12,
            leading: const Icon(StizeIcons.shield),
            title: Text(l10n.drawerPrivacy),
            trailing: const Icon(StizeIcons.chevronRight),
            onTap: () => context.push('/privacy'),
          ),
          if (version != null) ...[
            const SizedBox(height: 16),
            Text(
              version,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// `Route data: <Month Year>`, month localized to the active locale. Returns
  /// null when there's no date to show, so the caller omits the row entirely.
  String? _routeDataLabel(
    BuildContext context,
    AppLocalizations l10n,
    DateTime? date,
  ) {
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
