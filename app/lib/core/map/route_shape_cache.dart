import '../route_path.dart';

/// The route geometry the moving vehicles follow, per key: a direction's
/// route_id or a line number (they never collide, so one cache holds both).
///
/// A key is fetched once. A line with no shape caches `null` (its vehicles
/// stay on raw GPS). A failed lookup (a network blip) is not cached for the
/// session: it may be fetched again after [retryAfter], so a direction's
/// vehicles don't stay off the road until a reload.
class RouteShapeCache {
  RouteShapeCache({this.retryAfter = const Duration(seconds: 30)});

  final Duration retryAfter;

  final Map<String, RoutePath?> _paths = {};
  final Set<String> _fetching = {};
  final Map<String, DateTime> _failedAt = {};

  /// The path for [key]; null when unknown or when the line has no shape.
  RoutePath? operator [](String key) => _paths[key];

  /// Whether [key] has been resolved (to a path or to "no shape").
  bool has(String key) => _paths.containsKey(key);

  /// The keys of [keys] that should be fetched now, each claimed as in flight
  /// until [resolved] or [failed] is called for it.
  List<String> claim(Iterable<String> keys, DateTime now) {
    final out = <String>[];
    for (final key in keys.toSet()) {
      if (_paths.containsKey(key) || _fetching.contains(key)) continue;
      final failed = _failedAt[key];
      if (failed != null && now.difference(failed) < retryAfter) continue;
      _fetching.add(key);
      out.add(key);
    }
    return out;
  }

  /// A fetch for [key] came back (with [path], or null: the line has none).
  void resolved(String key, RoutePath? path) {
    _paths[key] = path;
    _failedAt.remove(key);
    _fetching.remove(key);
  }

  /// A fetch for [key] failed at [now]; it may be retried after [retryAfter].
  void failed(String key, DateTime now) {
    _failedAt[key] = now;
    _fetching.remove(key);
  }

  /// Store a path known from elsewhere (a line opened by the user).
  void put(String key, RoutePath? path) => _paths[key] = path;
}
