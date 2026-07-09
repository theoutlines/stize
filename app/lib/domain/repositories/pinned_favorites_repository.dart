import '../models/pinned_line.dart';

/// On-device store for the home-screen favourites carousel: pinned lines and
/// user-chosen custom names for any favourited entity. Favourite *stops* keep
/// living in [FavoritesRepository]; the carousel merges the two.
abstract class PinnedFavoritesRepository {
  Future<List<PinnedLine>> getLines();
  Future<void> addLine(PinnedLine line);
  Future<void> removeLine(String line);

  /// Custom names keyed by `stop:<stopId>` / `line:<number>` / `route:<id>`.
  Future<Map<String, String>> getCustomNames();

  /// Sets (or, with a null/blank value, clears) the custom name for [key].
  Future<void> setCustomName(String key, String? name);
}
