import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stize/data/feedback/stop_report_dedup.dart';
import 'package:stize/domain/repositories/feedback_repository.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/widgets/stop_report_sheet.dart';

class _FakeRepo implements FeedbackRepository {
  final reports = <Map<String, String?>>[];

  @override
  Future<void> submit({
    required String message,
    String? contact,
    required String appVersion,
    required String platform,
    required String locale,
  }) async {}

  @override
  Future<void> submitStopReport({
    required String stopId,
    required String category,
    String? comment,
    required String appVersion,
    required String platform,
    required String locale,
  }) async {
    reports.add({'stop': stopId, 'category': category, 'comment': comment});
  }
}

Widget _host(_FakeRepo repo) => ProviderScope(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(repo),
        appVersionProvider.overrideWith((ref) => Future.value('Stiže 1.0.0 (1)')),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StopReportSheet(stopId: '20147', stopName: 'Slavija')),
      ),
    );

FilledButton _send(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('send is disabled until a problem is picked; no comment field by default',
      (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    expect(find.byType(RadioListTile<String>), findsNWidgets(6));
    expect(find.byType(TextField), findsNothing);
    expect(_send(tester).onPressed, isNull);

    await tester.tap(find.text('Wrong lines'));
    await tester.pump();
    expect(_send(tester).onPressed, isNotNull);

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(repo.reports.single, {'stop': '20147', 'category': 'wrong_lines', 'comment': null});
    expect(find.text('Thanks, got it'), findsOneWidget);
  });

  testWidgets('"Something else" shows the text field and needs text', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    await tester.tap(find.text('Something else'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(_send(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'The pole is gone');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(repo.reports.single['comment'], 'The pole is gone');
  });

  testWidgets('the same report within 24 h is not sent again', (tester) async {
    await StopReportDedup().markSent('20147', 'wrong_name');
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    await tester.tap(find.text('Wrong name'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(repo.reports, isEmpty);
    expect(find.text('Already sent today'), findsOneWidget);
  });

  test('dedup window expires', () async {
    var now = DateTime(2026, 11, 23, 10);
    final dedup = StopReportDedup(now: () => now);
    await dedup.markSent('1', 'other');
    expect(await dedup.sentRecently('1', 'other'), isTrue);
    now = now.add(const Duration(hours: 25));
    expect(await dedup.sentRecently('1', 'other'), isFalse);
  });
}
