// Picks platform-appropriate geolocator LocationSettings. On the web this lets
// us pass WebSettings.maximumAge (which the base LocationSettings can't carry),
// so the browser may return a recent cached fix instantly instead of blocking
// for many seconds on a brand-new one.
export 'location_settings_io.dart'
    if (dart.library.js_interop) 'location_settings_web.dart';
