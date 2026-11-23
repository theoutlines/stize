import 'package:flutter/widgets.dart';

/// Edge-to-edge cards (owner, 2026-11-23, one-scroll home): inside the mobile
/// sheet transit cards run the full width, with no gaps and a hairline between
/// them, instead of rounded cards 4px apart. Lists and cards read this scope,
/// so the desktop panel keeps its rounded cards untouched.
class FlatCards extends InheritedWidget {
  const FlatCards({super.key, required super.child, this.flat = true});

  final bool flat;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FlatCards>()?.flat ?? false;

  @override
  bool updateShouldNotify(FlatCards old) => old.flat != flat;
}
