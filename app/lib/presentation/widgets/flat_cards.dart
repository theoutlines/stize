import 'package:flutter/widgets.dart';

/// Edge-to-edge cards (owner, 2026-11-23): transit cards run the full width,
/// with no gaps and a hairline between them, in EVERY list (Nearby, search,
/// stop board, desktop panel). The scope only exists to opt a list out.
class FlatCards extends InheritedWidget {
  const FlatCards({super.key, required super.child, this.flat = true});

  final bool flat;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FlatCards>()?.flat ?? true;

  @override
  bool updateShouldNotify(FlatCards old) => old.flat != flat;
}
