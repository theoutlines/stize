import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_config.dart';
import '../../core/foreground.dart';
import '../providers/providers.dart';

/// Keeps one stop's arrivals live: refetches every [kLiveRefreshInterval]
/// while the app is in the foreground and once on every return to it. Also
/// refreshes the jam banner on the same cadence (no-op while the jam flag is
/// off: the provider short-circuits to an empty board with no request).
///
/// Shared by the stop board (sheet, panel) and the full stop screen.
mixin StopLiveRefresh<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// The stop whose arrivals stay live.
  String get liveStopId;

  Timer? _refreshTimer;
  late final ForegroundResumeListener _resume = ForegroundResumeListener(() {
    if (mounted) refreshStopNow();
  });

  @override
  void initState() {
    super.initState();
    _refreshTimer?.cancel();
    _resume; // start listening for foreground returns
    _refreshTimer = Timer.periodic(kLiveRefreshInterval, (_) {
      if (appInForeground) refreshStopNow();
    });
  }

  void refreshStopNow() {
    ref.invalidate(arrivalsProvider(liveStopId));
    if (ref.read(jamDetectionEnabledProvider)) ref.invalidate(jamsProvider);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _resume.dispose();
    super.dispose();
  }
}
