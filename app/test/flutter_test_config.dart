import 'dart:async';

import 'package:stize/presentation/widgets/live_pulse_dot.dart';

/// Runs before every test file: endless decorative animations are switched
/// off so `pumpAndSettle` can settle.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LivePulseDot.animate = false;
  await testMain();
}
