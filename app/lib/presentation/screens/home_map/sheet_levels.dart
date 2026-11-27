import '../../widgets/guide/belgrade_guide.dart' show GuidePage;

/// A level of the one sheet (mobile) / panel (desktop) over Nearby (owner,
/// 2026-11-23: one sheet, levels stack inside it).
sealed class SheetLevel {
  const SheetLevel();
}

class StopLevel extends SheetLevel {
  const StopLevel(this.id, this.name);
  final String id;
  final String? name;
}

class MyStopsLevel extends SheetLevel {
  const MyStopsLevel();
}

class SettingsLevel extends SheetLevel {
  const SettingsLevel();
}

/// The feedback form ("Write to me"), opened straight from the menu.
class FeedbackLevel extends SheetLevel {
  const FeedbackLevel();
}

class GuideLevel extends SheetLevel {
  const GuideLevel(this.page);
  final GuidePage page;
}

/// The chain of open levels, oldest first; the last is what's shown, empty is
/// Nearby. Opening the level already on top never stacks it twice, and a trail
/// of stops is kept short.
class SheetLevelStack {
  final List<SheetLevel> _levels = [];

  /// Stops opened pin after pin shouldn't build a long trail.
  static const maxDepth = 8;

  bool get isEmpty => _levels.isEmpty;
  bool get isNotEmpty => _levels.isNotEmpty;
  int get length => _levels.length;

  /// What's shown; null = Nearby.
  SheetLevel? get top => _levels.isEmpty ? null : _levels.last;

  /// The level under the top one (what back returns to); null = Nearby.
  SheetLevel? get below =>
      _levels.length < 2 ? null : _levels[_levels.length - 2];

  /// The stop on top, if a stop is on top.
  StopLevel? get topStop => switch (top) {
    final StopLevel s => s,
    _ => null,
  };

  /// Open [level] unless the same level is already on top. Two levels are the
  /// same when they are of one kind with the same content (stop id, guide
  /// page).
  void open(SheetLevel level) {
    if (_same(top, level)) return;
    _levels.add(level);
    if (_levels.length > maxDepth) _levels.removeAt(0);
  }

  static bool _same(SheetLevel? a, SheetLevel b) => switch ((a, b)) {
    (StopLevel(id: final x), StopLevel(id: final y)) => x == y,
    (GuideLevel(page: final x), GuideLevel(page: final y)) => x == y,
    (FeedbackLevel(), FeedbackLevel()) => true,
    (MyStopsLevel(), MyStopsLevel()) => true,
    (SettingsLevel(), SettingsLevel()) => true,
    _ => false,
  };

  /// Back one level; returns the level that was closed.
  SheetLevel? pop() => _levels.isEmpty ? null : _levels.removeLast();

  /// Close every level: back to Nearby.
  void clear() => _levels.clear();
}
