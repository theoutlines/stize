import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'root_screen.dart';

/// `/stop/:id`: the home screen with that stop opened in its sheet / panel.
/// It hands the stop to the map through [linkedStopProvider]; the map opens it
/// once its style is ready.
class LinkedStopScreen extends ConsumerStatefulWidget {
  const LinkedStopScreen({super.key, required this.stopId, this.stopName});

  final String stopId;
  final String? stopName;

  @override
  ConsumerState<LinkedStopScreen> createState() => _LinkedStopScreenState();
}

class _LinkedStopScreenState extends ConsumerState<LinkedStopScreen> {
  @override
  void initState() {
    super.initState();
    // Set before the map mounts, so its first style load finds it.
    Future.microtask(() {
      ref.read(linkedStopProvider.notifier).state = (
        id: widget.stopId,
        name: widget.stopName,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const RootScreen();
}
