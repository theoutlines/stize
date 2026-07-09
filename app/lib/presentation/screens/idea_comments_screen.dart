import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';

class IdeaCommentsScreen extends ConsumerStatefulWidget {
  const IdeaCommentsScreen({super.key, required this.ideaId, required this.ideaText});

  final int ideaId;
  final String ideaText;

  @override
  ConsumerState<IdeaCommentsScreen> createState() => _IdeaCommentsScreenState();
}

class _IdeaCommentsScreenState extends ConsumerState<IdeaCommentsScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ref.read(ideasRepositoryProvider).addComment(widget.ideaId, text);
      _controller.clear();
      ref.invalidate(ideaCommentsProvider(widget.ideaId));
    } catch (_) {
      // best-effort; comments are a nice-to-have per spec
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final comments = ref.watch(ideaCommentsProvider(widget.ideaId));

    return Scaffold(
      appBar: AppBar(title: Text(widget.ideaText, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.ideaCommentsTitle, style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: comments.when(
              loading: () => const Center(child: CircularProgressIndicator.adaptive()),
              error: (err, st) => Center(child: Text(l10n.noNetworkTitle)),
              data: (list) {
                if (list.isEmpty) {
                  return Center(child: Text(l10n.ideaCommentsEmpty));
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) => ListTile(title: Text(list[i].text)),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 280,
                    decoration: InputDecoration(hintText: l10n.ideaCommentInputHint, border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(l10n.ideaCommentSubmit),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
