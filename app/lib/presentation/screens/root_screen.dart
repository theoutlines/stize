import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'about_screen.dart';
import 'my_stops_screen.dart';
import 'search_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [MyStopsScreen(), SearchScreen(), AboutScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.star_outline), selectedIcon: const Icon(Icons.star), label: l10n.navMyStops),
          NavigationDestination(icon: const Icon(Icons.search_outlined), selectedIcon: const Icon(Icons.search), label: l10n.navSearch),
          NavigationDestination(icon: const Icon(Icons.info_outline), selectedIcon: const Icon(Icons.info), label: l10n.navAbout),
        ],
      ),
    );
  }
}
