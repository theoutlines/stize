import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// In-app privacy policy (Part D#3) — not an external link. Concise, honest,
/// plain-language, l10n triple EN/RU/SR. DRAFT: the owner reviews the wording on
/// the preview before merge.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    Widget section(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacyTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(l10n.privacyIntro, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            section(l10n.privacyLocationTitle, l10n.privacyLocationBody),
            section(l10n.privacyAnalyticsTitle, l10n.privacyAnalyticsBody),
            section(l10n.privacyTrackersTitle, l10n.privacyTrackersBody),
            section(l10n.privacyFeedbackTitle, l10n.privacyFeedbackBody),
            section(l10n.privacyOpenSourceTitle, l10n.privacyOpenSourceBody),
          ],
        ),
      ),
    );
  }
}
