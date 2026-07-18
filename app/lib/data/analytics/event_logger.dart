import 'dart:async';
import 'dart:math';

import '../api/stigla_api_client.dart';

/// Anonymous product-analytics event logger.
///
/// Our own contour: events are batched and POSTed to the Stigla backend
/// (`/api/v1/events`), never to an external analytics vendor. By design it
/// carries **nothing** that could identify a person — no device id, no IP, no
/// coordinates, no free text. The only linkage is [_session]: a random id
/// generated in memory for this launch, never persisted, so server-side funnels
/// (e.g. stop_open -> vehicle_follow) can be read without any stable identity.
///
/// Fire-and-forget: [log] never awaits or throws, a failed flush is dropped
/// (no retry storm), and events still queued when the tab closes are simply
/// lost — acceptable for coarse product metrics.
///
/// Gating: until [setEnabled] is called the logger is *pending* — events are
/// buffered but nothing is sent. When the `product_analytics` flag resolves,
/// [setEnabled] either unlocks flushing (on) or drops the buffer and goes silent
/// (off). So with the flag OFF the logger makes **zero** network requests.
class EventLogger {
  EventLogger(this._client, {Random? random})
    : _session = _newSession(random ?? Random.secure());

  final StiglaApiClient _client;
  final String _session;

  // null = pending (flag not resolved yet); true/false = resolved gate.
  bool? _enabled;
  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;

  /// Flush when either threshold trips: N events buffered, or N seconds since
  /// the first buffered event. Both are small — analytics is low-volume and we
  /// favour freshness over batching efficiency.
  static const int flushThreshold = 20;
  static const Duration flushInterval = Duration(seconds: 15);

  /// Hard cap so a runaway caller can never grow the queue without bound; past
  /// it, new events are dropped (never block the UI, never OOM).
  static const int maxQueue = 200;

  static String _newSession(Random random) {
    // 16 hex chars — matches the backend's `[A-Za-z0-9_-]{1,32}` session shape.
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Resolve the gate from the `product_analytics` flag. Called once config
  /// loads. `on` unlocks flushing (and flushes anything buffered while pending);
  /// `off` discards the buffer and keeps the logger permanently silent.
  void setEnabled(bool on) {
    _enabled = on;
    if (!on) {
      _queue.clear();
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_queue.isNotEmpty) unawaited(flush());
  }

  /// Queue one event. `props` must contain only the enum values the backend
  /// allow-lists for `event`; anything else is stripped server-side. No-op once
  /// the flag has resolved to off.
  void log(String event, {Map<String, String>? props}) {
    if (_enabled == false) return;
    if (_queue.length >= maxQueue) return;
    _queue.add({
      'event': event,
      if (props != null && props.isNotEmpty) 'props': props,
      'session': _session,
    });
    // Only an *enabled* logger arms the flush timer. While pending (flag not yet
    // resolved) events are buffered without a timer — setEnabled(true) drains
    // them — so a disabled/pending logger schedules nothing (and never leaves a
    // timer pending in a widget test that doesn't mount the gate).
    if (_enabled != true) return;
    if (_queue.length >= flushThreshold) {
      unawaited(flush());
    } else {
      _timer ??= Timer(flushInterval, () => unawaited(flush()));
    }
  }

  /// Send whatever is queued as one batch. Safe to call any time; a no-op while
  /// pending or empty. Failures are swallowed — analytics never disrupts the UX.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_enabled != true || _queue.isEmpty) return;
    final batch = List<Map<String, dynamic>>.of(_queue);
    _queue.clear();
    try {
      await _client.postJson('/api/v1/events', body: {'events': batch});
    } catch (_) {
      // Fire-and-forget: drop the batch, do not requeue (avoids a retry storm
      // when the backend is unreachable).
    }
  }
}

/// The v1 event names and enum property values — mirrors the backend allow-list
/// in `backend/src/lib/productAnalytics.ts`. Kept as constants so call sites
/// can't typo an event or a value (which the backend would silently drop).
abstract final class Ev {
  static const appOpen = 'app_open';
  static const modeToggle = 'mode_toggle';
  static const stopOpen = 'stop_open';
  static const vehicleFollow = 'vehicle_follow';
  static const sortComfort = 'sort_comfort';
  static const lineFilter = 'line_filter';
  static const searchUsed = 'search_used';
  static const favoriteAdd = 'favorite_add';
  static const favoriteRemove = 'favorite_remove';

  // app_open.mode / mode_toggle.to
  static const modeOnDemand = 'on_demand';
  static const modeAquarium = 'aquarium';
  // stop_open.source
  static const srcPin = 'pin';
  static const srcNearby = 'nearby';
  static const srcFavorites = 'favorites';
  static const srcSearch = 'search';
  // vehicle_follow.source
  static const srcSheet = 'sheet';
  static const srcMarker = 'marker';
}

/// Maps a language code to the coarse cohort class the backend allow-lists for
/// `app_open.locale_class`: our three supported languages, else `other`. This is
/// the CLASS of the locale (a local-vs-tourist proxy), never the exact locale.
String localeClassOf(String languageCode) {
  switch (languageCode) {
    case 'sr':
    case 'ru':
    case 'en':
      return languageCode;
    default:
      return 'other';
  }
}
