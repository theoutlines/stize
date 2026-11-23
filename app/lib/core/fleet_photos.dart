import 'dart:convert';

/// One openly licensed photo for a fleet model or class, with the credit the
/// licence requires (author, licence, source page). Bundled as
/// `assets/data/fleet_photos.json`, keyed by the same id [FleetVehicle.id]
/// resolves to (a `models_catalog` key or a class `id`).
class FleetPhoto {
  const FleetPhoto({
    required this.url,
    required this.page,
    required this.author,
    required this.license,
  });

  /// Thumbnail URL (upload.wikimedia.org, standard 500px step).
  final String url;

  /// The file's description page on Wikimedia Commons (licence + full credit).
  final String page;
  final String author;
  final String license;

  /// Parses the bundled asset. Returns an empty map on any shape problem, so a
  /// bad asset only hides photos and never breaks the card.
  static Map<String, FleetPhoto> parseAll(String source) {
    try {
      final root = jsonDecode(source);
      if (root is! Map || root['photos'] is! Map) return const {};
      final out = <String, FleetPhoto>{};
      (root['photos'] as Map).forEach((key, value) {
        if (key is! String || value is! Map) return;
        final url = value['url'], page = value['page'];
        final author = value['author'], license = value['license'];
        if (url is String &&
            url.startsWith('https://upload.wikimedia.org/') &&
            page is String &&
            author is String &&
            license is String) {
          out[key] = FleetPhoto(
            url: url,
            page: page,
            author: author,
            license: license,
          );
        }
      });
      return out;
    } catch (_) {
      return const {};
    }
  }
}
