import 'package:flutter/material.dart';
import 'package:stize/presentation/widgets/stop_board.dart';

/// A stop's arrivals board on a bare page, for widget tests: the same
/// [StopBoard] the map's stop sheet and desktop panel host.
class StopBoardPage extends StatelessWidget {
  const StopBoardPage({super.key, required this.stopId, this.initialStopName});

  final String stopId;
  final String? initialStopName;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: StopBoard(stopId: stopId, initialStopName: initialStopName),
  );
}
