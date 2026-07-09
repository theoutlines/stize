import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Platform-adaptive presentation helpers.
///
/// The app is built on Material; on *native iOS* we nudge the feel toward
/// Cupertino (page transitions with the left-edge back gesture, action sheets,
/// adaptive controls). Android keeps Material (its native language). Web stays
/// neutral — it has no imposed platform language — so we gate on `!kIsWeb`,
/// meaning even iOS Safari renders the neutral Material look, not Cupertino.
///
/// Fonts are intentionally left to the framework: with no `fontFamily` set on
/// the theme, each platform uses its system sans-serif (San Francisco on iOS,
/// Roboto on Android, the browser default on web) — exactly what we want.
bool get isCupertino => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// A go_router [Page] that transitions like the native platform: a
/// [CupertinoPage] on iOS (so the left-edge swipe-back gesture works), a
/// [MaterialPage] elsewhere.
Page<T> adaptivePage<T>({required Widget child, LocalKey? key}) => isCupertino
    ? CupertinoPage<T>(key: key, child: child)
    : MaterialPage<T>(key: key, child: child);

/// A [Route] that transitions like the native platform — the imperative
/// equivalent of [adaptivePage], for `Navigator.push`.
Route<T> adaptiveRoute<T>(WidgetBuilder builder) => isCupertino
    ? CupertinoPageRoute<T>(builder: builder)
    : MaterialPageRoute<T>(builder: builder);
