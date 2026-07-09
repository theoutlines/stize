import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../data/api/api_exceptions.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';
import 'idea_comments_screen.dart';

class IdeasScreen extends ConsumerStatefulWidget {
  const IdeasScreen({super.key, this.onOpenDrawer});

  /// Opens the app's navigation drawer (owned by the root scaffold).
  final VoidCallback? onOpenDrawer;

  @override
  ConsumerState<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends ConsumerState<IdeasScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(AppLocalizations l10n) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await ref.read(ideasControllerProvider.notifier).submit(text);
      _controller.clear();
    } on RateLimitedException {
      setState(() => _errorText = l10n.ideaRateLimited);
    } catch (_) {
      setState(() => _errorText = l10n.noNetworkTitle);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ideas = ref.watch(ideasControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navIdeas),
        leading: widget.onOpenDrawer == null
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                onPressed: widget.onOpenDrawer,
              ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 280,
                    decoration: InputDecoration(
                      hintText: l10n.ideaInputHint,
                      errorText: _errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submitting ? null : () => _submit(l10n),
                  child: Text(l10n.ideaSubmit),
                ),
              ],
            ),
          ),
          Expanded(
            child: ideas.when(
              loading: () => const Center(child: CircularProgressIndicator.adaptive()),
              error: (err, st) => EmptyState(
                icon: Icons.wifi_off_rounded,
                title: l10n.noNetworkTitle,
              ),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.lightbulb_outline,
                    title: l10n.ideasEmptyTitle,
                    subtitle: l10n.ideasEmptySubtitle,
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final idea = list[i];
                    return ListTile(
                      title: Text(idea.text),
                      subtitle: Text(l10n.ideaVotesCount(idea.votes)),
                      leading: IconButton(
                        icon: Icon(
                          idea.hasVoted
                              ? Icons.arrow_circle_up
                              : Icons.arrow_circle_up_outlined,
                        ),
                        color: idea.hasVoted
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        onPressed: () => ref
                            .read(ideasControllerProvider.notifier)
                            .toggleVote(idea.id),
                      ),
                      onTap: () => Navigator.of(context).push(
                        adaptiveRoute(
                          (_) => IdeaCommentsScreen(
                            ideaId: idea.id,
                            ideaText: idea.text,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
