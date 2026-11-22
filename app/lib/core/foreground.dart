import 'package:flutter/widgets.dart';

/// True while the app (or the browser tab, on web) is in the foreground.
///
/// Live polls use this to skip their tick while hidden: a locked phone or a
/// background tab would otherwise keep hitting the backend every 30s for a
/// board nobody is looking at. Every such request counts against the shared
/// daily Workers quota, which matters at Expo-scale traffic.
bool get appInForeground {
  final s = WidgetsBinding.instance.lifecycleState;
  return s == null || s == AppLifecycleState.resumed;
}

/// Calls [onResume] when the app returns to the foreground, so a board that
/// skipped its ticks while hidden refreshes immediately instead of waiting up
/// to a full poll interval.
class ForegroundResumeListener with WidgetsBindingObserver {
  ForegroundResumeListener(this.onResume) {
    WidgetsBinding.instance.addObserver(this);
  }

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}
