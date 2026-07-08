import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'about_screen.dart';
import 'home_map_screen.dart';
import 'ideas_screen.dart';

class RootScreen extends ConsumerStatefulWidget {
  const RootScreen({super.key});

  @override
  ConsumerState<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends ConsumerState<RootScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: keeps the offline stop/line reference fresh without
    // blocking startup. Safe to ignore failures — the live API is always
    // tried first anyway.
    unawaited(ref.read(gtfsOfflineCacheProvider).refreshIfStale());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [HomeMapScreen(), IdeasScreen(), AboutScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.map_outlined), selectedIcon: const Icon(Icons.map), label: l10n.navHome),
          NavigationDestination(icon: const Icon(Icons.lightbulb_outline), selectedIcon: const Icon(Icons.lightbulb), label: l10n.navIdeas),
          NavigationDestination(icon: const Icon(Icons.info_outline), selectedIcon: const Icon(Icons.info), label: l10n.navAbout),
        ],
      ),
    );
  }
}
