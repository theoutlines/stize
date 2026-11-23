import 'package:flutter/material.dart';

import '../stize_tokens.dart';

/// PageFrame's column: a standalone page (Settings, About, Privacy) sits in
/// one centred column on a wide window, header included, so the title lines up
/// with the content. On a phone it is the full width.
class StizePageColumn extends StatelessWidget {
  const StizePageColumn({super.key, required this.child});

  /// The widest a page's column gets.
  static const double maxWidth = 680;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: StizeColors.of(context).bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
