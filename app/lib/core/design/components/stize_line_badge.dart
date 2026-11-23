import 'package:flutter/material.dart';

import '../../../domain/models/vehicle_type.dart';
import '../../map_support.dart';
import '../stize_tokens.dart';

/// Line badge (design system: components/LineBadge): the line number on its
/// transit colour, white `line-number` text, hugging the number. Two sizes:
/// 22 (lists, charts) and 28 (headers).
class StizeLineBadge extends StatelessWidget {
  const StizeLineBadge({
    super.key,
    required this.line,
    this.type,
    this.big = false,
  });

  final String line;

  /// Defaults to the line's type from the line index.
  final VehicleType? type;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Container(
      constraints: BoxConstraints(minWidth: big ? 36 : 28),
      height: big ? 28 : 24,
      padding: const EdgeInsets.symmetric(horizontal: StizeSpace.space2),
      decoration: BoxDecoration(
        color: vehicleColor(type ?? lineTypeOf(line)),
        borderRadius: BorderRadius.circular(StizeRadius.radiusXs),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          line,
          style: StizeType.lineNumber.copyWith(
            color: c.onTransit,
            fontSize: big ? 16 : 12,
          ),
        ),
      ),
    );
  }
}
