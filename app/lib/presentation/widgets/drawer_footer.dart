import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_links.dart';
import '../../core/external_link.dart';
import '../../data/api/api_exceptions.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../../core/design/stize_icons.dart';

/// Pushes Flutter's licence page with the app's AGPL header + repo link.
void openLicensesPage(
  BuildContext context,
  AppLocalizations l10n,
  String? version,
) {
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
          applicationName: 'Stiže',
          applicationVersion: version,
          applicationLegalese: '${l10n.licensesLegalese}\n$kRepoUrl',
        ),
      ),
    ),
  );
}

/// The two-action feedback sheet: the in-app form ("Write to me", gated by the
/// `feedback_form` flag) and a link to the public GitHub issues (technical
/// users). The contact email is deliberately never shown.
void showFeedbackSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => PointerInterceptor(
      child: ((sheetContext) => Consumer(
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
                    leading: const Icon(StizeIcons.edit),
                    title: Text(l10n.feedbackWriteToMe),
                    subtitle: Text(l10n.feedbackWriteToMeSubtitle),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      showFeedbackForm(context);
                    },
                  ),
                ListTile(
                  leading: const Icon(StizeIcons.bug),
                  title: Text(l10n.feedbackGithubIssues),
                  subtitle: Text(l10n.feedbackGithubIssuesSubtitle),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    openExternalUrl(kRepoIssuesUrl);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ))(ctx),
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
    builder: (ctx) => PointerInterceptor(
      child: ((_) => const Padding(
        // Lift above the keyboard.
        padding: EdgeInsets.only(bottom: 0),
        child: FeedbackForm(),
      ))(ctx),
    ),
  );
}

class FeedbackForm extends ConsumerStatefulWidget {
  const FeedbackForm({super.key, this.onSent, this.showTitle = true});

  /// Called after a successful send instead of popping a route (the form as a
  /// level in the map's sheet/panel).
  final VoidCallback? onSent;

  /// The sheet shows its own title; as a level the header carries it.
  final bool showTitle;

  @override
  ConsumerState<FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends ConsumerState<FeedbackForm> {
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
      await ref
          .read(feedbackRepositoryProvider)
          .submit(
            message: message,
            contact: _contactController.text,
            appVersion: version,
            platform: _platform,
            locale: locale,
          );
      if (!mounted) return;
      if (widget.onSent != null) {
        widget.onSent!();
      } else {
        navigator.pop();
      }
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
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTitle) ...[
            Text(l10n.feedbackFormTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
          ],
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
