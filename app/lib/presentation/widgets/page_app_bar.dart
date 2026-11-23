import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/stize_icons.dart';

/// PageFrame's header: a plain back arrow and a left-aligned title (owner,
/// 2026-11-23). Back pops, or goes to the map when the page was opened by link.
PreferredSizeWidget pageAppBar(BuildContext context, String title) => AppBar(
  leading: IconButton(
    icon: const Icon(StizeIcons.back),
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: () => context.canPop() ? context.pop() : context.go('/'),
  ),
  centerTitle: false,
  titleSpacing: 4,
  title: Text(title),
);
