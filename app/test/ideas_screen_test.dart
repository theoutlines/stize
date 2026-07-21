import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/data/api/api_exceptions.dart';
import 'package:stize/domain/models/idea.dart';
import 'package:stize/domain/repositories/ideas_repository.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/screens/ideas_screen.dart';

class _FakeIdeasRepository implements IdeasRepository {
  _FakeIdeasRepository(this._ideas);
  List<Idea> _ideas;
  bool throwRateLimit = false;

  @override
  Future<List<Idea>> list() async => _ideas;

  @override
  Future<Idea> submit(String text) async {
    if (throwRateLimit) throw const RateLimitedException('rate limited');
    final idea = Idea(id: 999, text: text, votes: 0, createdAt: DateTime.now(), hasVoted: false);
    _ideas = [..._ideas, idea];
    return idea;
  }

  @override
  Future<({int votes, bool hasVoted})> toggleVote(int ideaId) async {
    final idea = _ideas.firstWhere((i) => i.id == ideaId);
    final newHasVoted = !idea.hasVoted;
    final newVotes = idea.votes + (newHasVoted ? 1 : -1);
    _ideas = [
      for (final i in _ideas)
        if (i.id == ideaId) i.copyWith(votes: newVotes, hasVoted: newHasVoted) else i,
    ];
    return (votes: newVotes, hasVoted: newHasVoted);
  }

  @override
  Future<List<IdeaComment>> listComments(int ideaId) async => [];

  @override
  Future<IdeaComment> addComment(int ideaId, String text) async {
    return IdeaComment(id: 1, text: text, createdAt: DateTime.now());
  }
}

Widget _wrap(IdeasRepository repo) {
  return ProviderScope(
    overrides: [ideasRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const IdeasScreen(),
    ),
  );
}

void main() {
  testWidgets('shows the empty state when there are no ideas', (tester) async {
    await tester.pumpWidget(_wrap(_FakeIdeasRepository([])));
    await tester.pumpAndSettle();

    expect(find.text('No ideas yet'), findsOneWidget);
  });

  testWidgets('lists ideas with vote counts', (tester) async {
    final repo = _FakeIdeasRepository([
      Idea(id: 1, text: 'Add dark mode', votes: 3, createdAt: DateTime.now(), hasVoted: false),
    ]);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Add dark mode'), findsOneWidget);
    expect(find.text('3 votes'), findsOneWidget);
  });

  testWidgets('submitting a new idea adds it to the list', (tester) async {
    final repo = _FakeIdeasRepository([]);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Show vehicle model');
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();

    expect(find.text('Show vehicle model'), findsOneWidget);
  });

  testWidgets('shows a friendly message when rate-limited', (tester) async {
    final repo = _FakeIdeasRepository([])..throwRateLimit = true;
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Another idea');
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();

    expect(find.text('One new idea at a time — try again in a few minutes.'), findsOneWidget);
  });

  testWidgets('tapping the vote icon toggles the vote', (tester) async {
    final repo = _FakeIdeasRepository([
      Idea(id: 1, text: 'Add dark mode', votes: 0, createdAt: DateTime.now(), hasVoted: false),
    ]);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_circle_up_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_circle_up_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_circle_up), findsOneWidget);
    expect(find.text('1 vote'), findsOneWidget);
  });
}
