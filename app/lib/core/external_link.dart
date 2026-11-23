import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// Open an outward link (donations, GitHub, map attribution, route alerts).
///
/// MUST be called synchronously from inside the tap/gesture callback — do NOT
/// await anything before it, and pass a value that is already in hand (e.g. a
/// URL already resolved into provider state), never one you fetch on tap.
///
/// Why: some iOS WebKit wrappers (notably Arc) enforce the browser's
/// user-activation window far more strictly than Safari and will silently
/// swallow a `window.open(_blank)` popup that isn't fired directly within the
/// gesture — the donate banner would show its tap ripple but never open. On web
/// we therefore navigate the SAME tab (`_self`): same-tab navigation is never
/// popup-blocked, in any wrapper, so the external page always opens. Leaving the
/// app to reach that page is acceptable for these outward links. On native
/// (iOS/Android app) we hand off to the external browser as before.
Future<bool> openExternalUrl(String url) {
  final uri = Uri.parse(url);
  if (kIsWeb) {
    // A new tab, so leaving for Support/GitHub never replaces the app (owner,
    // 2026-11-23). Called synchronously inside the tap, so the browser's user
    // activation lets the tab open without a popup block.
    return launchUrl(uri, webOnlyWindowName: '_blank');
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
