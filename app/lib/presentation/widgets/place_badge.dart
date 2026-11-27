import 'package:flutter/material.dart';

/// The badges, one PNG per POI class and theme (tool/sprite builds them).
const _badgeDir = 'assets/poi/';

/// A place found by search, drawn with the badge it has on the map: the
/// category disc of the basemap POI sprite (museum, park, cafe…). A street or
/// an address, which has no badge on the map, gets the neutral `address` disc.
class PlaceBadge extends StatelessWidget {
  const PlaceBadge({super.key, required this.kind, this.size = 28});

  /// The POI class, or null for a street / address.
  final String? kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).brightness == Brightness.dark
        ? 'dark'
        : 'light';
    Widget badge(String name, {bool fallback = true}) => Image.asset(
      '$_badgeDir$theme/$name' '.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      // A class the sprite doesn't draw falls back to the neutral disc.
      errorBuilder: fallback
          ? (_, _, _) => badge('address', fallback: false)
          : null,
    );
    return badge(kind ?? 'address');
  }
}
