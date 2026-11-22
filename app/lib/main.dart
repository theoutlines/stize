import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'presentation/app.dart';

void main() {
  // Plain paths (stize.app/stop/20147), not #/ fragments, so a stop link works
  // when pasted anywhere. Old #/ links are rewritten in web/index.html.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  // Warm the custom stop-pin SVGs into the flutter_svg cache before the map
  // rasterizes its stop pins (via addImageFromWidget), so a pin never captures
  // a half-loaded icon.
  for (final asset in const [
    'assets/icons/trolleybus.svg',
    'assets/icons/bus_multiple.svg',
  ]) {
    final loader = SvgAssetLoader(asset);
    svg.cache.putIfAbsent(loader.cacheKey(null), () => loader.loadBytes(null));
  }

  // Bundled fonts are not pub packages, so their SIL OFL licences are added to
  // the licence page by hand.
  LicenseRegistry.addLicense(() async* {
    for (final (family, asset) in const [
      ('Uncut Sans', 'assets/fonts/UncutSans-OFL.txt'),
      ('Geist Mono', 'assets/fonts/GeistMono-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString(asset));
    }
  });

  runApp(const ProviderScope(child: StiglaApp()));
}
