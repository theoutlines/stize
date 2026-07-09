import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'presentation/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Warm the trolleybus SVG into the flutter_svg cache before the map rasterizes
  // its stop pins (via addImageFromWidget), so the trolley pin never captures a
  // half-loaded icon.
  const loader = SvgAssetLoader('assets/icons/trolleybus.svg');
  svg.cache.putIfAbsent(loader.cacheKey(null), () => loader.loadBytes(null));

  runApp(const ProviderScope(child: StiglaApp()));
}
