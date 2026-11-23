import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'presentation/app.dart';

void main() {
  // Plain paths (stize.app/stop/20147), not #/ fragments, so a stop link works
  // when pasted anywhere. Old #/ links are rewritten in web/index.html.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  // Bundled fonts are not pub packages, so their SIL OFL licences are added to
  // the licence page by hand.
  LicenseRegistry.addLicense(() async* {
    for (final (family, asset) in const [
      ('Uncut Sans', 'assets/fonts/UncutSans-OFL.txt'),
      ('Geist Mono', 'assets/fonts/GeistMono-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString(asset));
    }
  });

  runApp(const ProviderScope(child: StiglaApp()));
}
