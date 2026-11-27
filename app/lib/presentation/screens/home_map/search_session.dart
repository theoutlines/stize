/// The map's search mode on desktop: whether the persistent search drives the
/// panel, and whether this session already logged `search_used`.
///
/// The results themselves come from the shared Nearby view (the same one the
/// mobile pill drives), which runs the query and drops stale answers. The
/// `search_used` event is logged once per session (a session ends when the
/// query is cleared), not once per keystroke.
class SearchSession {
  /// Search mode is on (the results view replaces the panel content).
  bool active = false;

  bool _logged = false;

  /// The query changed (a keystroke): search mode on.
  void typed() => active = true;

  /// True once per session: log `search_used` now.
  bool firstUse() {
    if (_logged) return false;
    _logged = true;
    return true;
  }

  /// The query was cleared: search mode off, a new session.
  void clear() {
    active = false;
    _logged = false;
  }
}
