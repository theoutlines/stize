import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stize/data/analytics/event_logger.dart';
import 'package:stize/data/api/stigla_api_client.dart';

/// Records every POST body the logger sends, so tests can assert on the batches
/// (and, crucially, on there being none when the flag is off).
class _Recorder {
  final List<List<dynamic>> batches = [];

  StiglaApiClient client() {
    final mock = MockClient((req) async {
      final decoded = jsonDecode(req.body) as Map<String, dynamic>;
      batches.add(decoded['events'] as List<dynamic>);
      return http.Response('{"accepted":1}', 202);
    });
    return StiglaApiClient(httpClient: mock);
  }
}

void main() {
  test('sends nothing while the flag is off (zero requests)', () async {
    final rec = _Recorder();
    final logger = EventLogger(rec.client())..setEnabled(false);
    logger.log(Ev.searchUsed);
    logger.log(Ev.stopOpen, props: {'source': Ev.srcPin});
    await logger.flush();
    expect(rec.batches, isEmpty);
  });

  test('buffers while pending, then flushes once enabled', () async {
    final rec = _Recorder();
    final logger = EventLogger(rec.client());
    // Pending (setEnabled not called yet): queued, but nothing sent.
    logger.log(Ev.searchUsed);
    await logger.flush();
    expect(rec.batches, isEmpty);
    // Enabling flushes what was buffered.
    logger.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    expect(rec.batches, hasLength(1));
    expect(rec.batches.first, hasLength(1));
    expect(rec.batches.first.first['event'], Ev.searchUsed);
  });

  test('drops the buffer when the flag resolves off', () async {
    final rec = _Recorder();
    final logger = EventLogger(rec.client());
    logger.log(Ev.searchUsed); // pending
    logger.setEnabled(false); // resolved off -> buffer cleared, silent
    await logger.flush();
    expect(rec.batches, isEmpty);
  });

  test('flush sends one batch with event, props and a stable session id', () async {
    final rec = _Recorder();
    final logger = EventLogger(rec.client())..setEnabled(true);
    logger.log(Ev.appOpen, props: {'mode': Ev.modeOnDemand, 'locale_class': 'sr'});
    logger.log(Ev.sortComfort);
    await logger.flush();

    expect(rec.batches, hasLength(1));
    final batch = rec.batches.single;
    expect(batch, hasLength(2));
    expect(batch[0]['event'], Ev.appOpen);
    expect(batch[0]['props'], {'mode': Ev.modeOnDemand, 'locale_class': 'sr'});
    // A no-property event carries no 'props' key.
    expect(batch[1]['event'], Ev.sortComfort);
    expect(batch[1].containsKey('props'), isFalse);
    // Same ephemeral session id across events from one logger instance.
    expect(batch[0]['session'], isNotEmpty);
    expect(batch[1]['session'], batch[0]['session']);
  });

  test('auto-flushes when the size threshold is reached', () async {
    final rec = _Recorder();
    final logger = EventLogger(rec.client())..setEnabled(true);
    for (var i = 0; i < EventLogger.flushThreshold; i++) {
      logger.log(Ev.lineFilter);
    }
    await Future<void>.delayed(Duration.zero);
    expect(rec.batches, hasLength(1));
    expect(rec.batches.single, hasLength(EventLogger.flushThreshold));
  });

  test('localeClassOf maps supported languages and buckets the rest', () {
    expect(localeClassOf('sr'), 'sr');
    expect(localeClassOf('ru'), 'ru');
    expect(localeClassOf('en'), 'en');
    expect(localeClassOf('fr'), 'other');
    expect(localeClassOf('de'), 'other');
  });
}
