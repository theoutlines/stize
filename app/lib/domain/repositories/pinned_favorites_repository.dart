/// On-device store for user-chosen custom names of favourited entities.
/// Favourite *stops* themselves live in [FavoritesRepository].
abstract class PinnedFavoritesRepository {
  /// Custom names keyed by `stop:<stopId>` / `line:<number>` / `route:<id>`.
  Future<Map<String, String>> getCustomNames();

  /// Sets (or, with a null/blank value, clears) the custom name for [key].
  Future<void> setCustomName(String key, String? name);
}
