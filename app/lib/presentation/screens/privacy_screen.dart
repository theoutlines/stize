import 'package:stize/presentation/widgets/page_app_bar.dart';
import 'package:stize/core/design/components/stize_page_column.dart';
import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';

import '../../l10n/app_localizations.dart';

/// In-app privacy policy (Part D#3) — not an external link. Concise, honest,
/// plain-language, l10n triple EN/RU/SR. Wording reviewed and approved (EN/RU;
/// SR is a translated mirror).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget section(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: StizeText.of(context).label),
          const SizedBox(height: 8),
          Text(body, style: StizeText.of(context).body),
        ],
      ),
    );

    return StizePageColumn(
      child: Scaffold(
        appBar: pageAppBar(context, l10n.privacyTitle),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(l10n.privacyIntro, style: StizeText.of(context).body),
              const SizedBox(height: 24),
              section(l10n.privacyLocationTitle, l10n.privacyLocationBody),
              section(l10n.privacyAnalyticsTitle, l10n.privacyAnalyticsBody),
              section(l10n.privacyTrackersTitle, l10n.privacyTrackersBody),
              section(l10n.privacyFeedbackTitle, l10n.privacyFeedbackBody),
              section(l10n.privacyServicesTitle, l10n.privacyServicesBody),
              section(l10n.privacyOpenSourceTitle, l10n.privacyOpenSourceBody),
            ],
          ),
        ),
      ),
    );
  }
}
