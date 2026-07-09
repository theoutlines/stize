import 'vehicle_type.dart';

/// A transport line the user pinned for quick access in the home-screen
/// carousel. Stored on-device only. Custom display names live separately (a
/// key/value store keyed by `line:<number>`) so renaming never loses the
/// official origin→destination detail.
class PinnedLine {
  const PinnedLine({
    required this.line,
    required this.vehicleType,
    required this.origin,
    required this.destination,
  });

  final String line;
  final VehicleType vehicleType;
  final String origin;
  final String destination;

  String get officialName => line;
  String get routeLabel => '$origin → $destination';

  Map<String, dynamic> toJson() => {
    'line': line,
    'vehicle_type': vehicleType.name,
    'origin': origin,
    'destination': destination,
  };

  factory PinnedLine.fromJson(Map<String, dynamic> json) {
    return PinnedLine(
      line: json['line'] as String,
      vehicleType: VehicleType.values.byName(json['vehicle_type'] as String),
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
    );
  }
}
