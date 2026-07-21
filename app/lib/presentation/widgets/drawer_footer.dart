import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_links.dart';
import '../../data/api/api_exceptions.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// The drawer's "about & contact" footer (Part D): an indie feedback banner, the
/// open-source licenses, the privacy policy, an optional donate link, and a
/// dimmed version line pinned at the very bottom. Appended BELOW the existing
/// drawer items — the rest of the drawer is untouched (Part D non-goals).
class DrawerFooter extends ConsumerWidget {
  const DrawerFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final donateUrl = ref.watch(donateUrlProvider);
    final version = ref.watch(appVersionProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: _FeedbackBanner(onTap: () => showFeedbackSheet(context)),
        ),
        _FooterTile(
          icon: Icons.description_outlined,
          label: l10n.drawerLicenses,
          onTap: () => _openLicenses(context, l10n, version),
        ),
        _FooterTile(
          icon: Icons.privacy_tip_outlined,
          label: l10n.drawerPrivacy,
          onTap: () {
            Navigator.of(context).pop(); // close the drawer
            context.push('/privacy');
          },
        ),
        // Donate is reserved behind the KV `config:donate_url`: hidden while
        // empty, shown (opening the URL) once the owner sets it. No new flag.
        if (donateUrl != null)
          _FooterTile(
            icon: Icons.favorite_outline,
            label: l10n.drawerDonate,
            onTap: () => launchUrl(Uri.parse(donateUrl),
                mode: LaunchMode.externalApplication),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Text(
            version ?? '',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }

  void _openLicenses(
      BuildContext context, AppLocalizations l10n, String? version) {
    // Flutter's LicenseRegistry already covers every bundled package; we add the
    // app's own AGPL header + repo link above the list via the legalese slot.
    //
    // The app bar must stay OPAQUE and ON TOP of the scrolling list (owner
    // acceptance #2 — package headers were bleeding through a see-through bar).
    // Push LicensePage inside a Theme whose AppBar has a solid surface fill +
    // scrolled-under elevation, so content passes cleanly under it.
    final base = Theme.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Theme(
          data: base.copyWith(
            appBarTheme: base.appBarTheme.copyWith(
              backgroundColor: base.colorScheme.surface,
              surfaceTintColor: base.colorScheme.surfaceTint,
              scrolledUnderElevation: 3,
              elevation: 0,
            ),
          ),
          child: LicensePage(
            applicationName: 'Stigla',
            applicationVersion: version,
            applicationLegalese: '${l10n.licensesLegalese}\n$kRepoUrl',
          ),
        ),
      ),
    );
  }
}

/// The indie framing banner: creator photo + a short line. Tapping opens the
/// feedback actions sheet.
class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _CreatorAvatar(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.drawerFeedbackBannerLine,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// The creator photo — `assets/images/creator.jpg`, with a neutral placeholder
/// avatar if it's missing at build time (flagged in the report).
class _CreatorAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipOval(
      child: Image.asset(
        'assets/images/creator.jpg',
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: 44,
          height: 44,
          color: theme.colorScheme.secondaryContainer,
          child: Icon(Icons.person,
              color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}

class _FooterTile extends StatelessWidget {
  const _FooterTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(label, style: theme.textTheme.bodyMedium),
      onTap: onTap,
    );
  }
}

/// The two-action feedback sheet: the in-app form ("Write to me", gated by the
/// `feedback_form` flag) and a link to the public GitHub issues (technical
/// users). The contact email is deliberately never shown.
void showFeedbackSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        final formEnabled = ref.watch(feedbackFormEnabledProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The form action disappears entirely when the killswitch is off.
              if (formEnabled)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l10n.feedbackWriteToMe),
                  subtitle: Text(l10n.feedbackWriteToMeSubtitle),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showFeedbackForm(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(l10n.feedbackGithubIssues),
                subtitle: Text(l10n.feedbackGithubIssuesSubtitle),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  launchUrl(Uri.parse(kRepoIssuesUrl),
                      mode: LaunchMode.externalApplication);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
}

/// The in-app feedback form sheet: a message field + an optional contact field.
/// No mailto, no exposed email. App version / platform / locale are attached
/// automatically on submit.
void showFeedbackForm(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const Padding(
      // Lift above the keyboard.
      padding: EdgeInsets.only(bottom: 0),
      child: _FeedbackForm(),
    ),
  );
}

class _FeedbackForm extends ConsumerStatefulWidget {
  const _FeedbackForm();

  @override
  ConsumerState<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends ConsumerState<_FeedbackForm> {
  final _messageController = TextEditingController();
  final _contactController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      setState(() => _error = l10n.feedbackEmptyValidation);
      return;
    }
    // Capture everything context-derived BEFORE the async gap.
    final locale = Localizations.localeOf(context).languageCode;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    final version = await ref.read(appVersionProvider.future);
    try {
      await ref.read(feedbackRepositoryProvider).submit(
            message: message,
            contact: _contactController.text,
            appVersion: version,
            platform: _platform,
            locale: locale,
          );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.feedbackSent)));
    } on RateLimitedException {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = l10n.feedbackErrorRateLimited;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = l10n.feedbackErrorGeneric;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.feedbackFormTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: l10n.feedbackMessageLabel,
              hintText: l10n.feedbackMessageHint,
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contactController,
            decoration: InputDecoration(
              labelText: l10n.feedbackContactLabel,
              hintText: l10n.feedbackContactHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _sending ? null : _submit,
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.feedbackSend),
          ),
        ],
      ),
    );
  }
}
