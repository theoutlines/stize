import 'package:flutter/material.dart';

import 'stize_tokens.dart';

/// The type scale with its default colour, by token name.
///
/// Use instead of `Theme.of(context).textTheme.*` (Material's names): the
/// colours match the theme's text theme, so a swap is pixel-identical.
/// `StizeText.of(context).caption.copyWith(...)` for local tweaks.
class StizeText {
  const StizeText(this.c);

  factory StizeText.of(BuildContext context) =>
      StizeText(StizeColors.of(context));

  /// For helpers that get the theme rather than a context.
  factory StizeText.ofTheme(ThemeData theme) =>
      StizeText(theme.extension<StizeColors>() ?? StizeColors.dark);

  final StizeColors c;

  TextStyle get etaHero => StizeType.etaHero.copyWith(color: c.ink);
  TextStyle get bigNumber => StizeType.bigNumber.copyWith(color: c.ink);
  TextStyle get heroTitle => StizeType.heroTitle.copyWith(color: c.ink);
  TextStyle get h1 => StizeType.h1.copyWith(color: c.ink);
  TextStyle get date => StizeType.date.copyWith(color: c.ink);
  TextStyle get section => StizeType.section.copyWith(color: c.ink);
  TextStyle get body => StizeType.body.copyWith(color: c.ink);
  TextStyle get label => StizeType.label.copyWith(color: c.ink);
  TextStyle get control => StizeType.control.copyWith(color: c.ink);
  TextStyle get caption => StizeType.caption.copyWith(color: c.ink60);
  TextStyle get note => StizeType.note.copyWith(color: c.ink50);
}
