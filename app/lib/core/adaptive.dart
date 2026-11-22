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
/// Fonts: with the Stiže design system every platform uses
/// the bundled Uncut Sans, so the app reads as one product on iOS, Android and
/// web; this replaced the earlier "system font per platform" choice on
/// 2026-11-22. Only the font changed: transitions, the iOS back gesture and the
/// adaptive controls here stay platform-native.
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
