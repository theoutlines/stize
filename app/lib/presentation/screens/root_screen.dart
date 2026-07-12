import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../widgets/app_drawer.dart';
import 'home_map_screen.dart';
import 'ideas_screen.dart';

class RootScreen extends ConsumerStatefulWidget {
  const RootScreen({super.key});

  @override
  ConsumerState<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends ConsumerState<RootScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: keeps the offline stop/line reference fresh without
    // blocking startup. Safe to ignore failures — the live API is always
    // tried first anyway.
    unawaited(ref.read(gtfsOfflineCacheProvider).refreshIfStale());
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(
        currentIndex: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
      // A single Scaffold owns the drawer; the section pages switch inside it,
      // and each opens the drawer through [_openDrawer] (hamburger / edge swipe).
      body: IndexedStack(
        index: _index,
        children: [
          HomeMapScreen(onOpenDrawer: _openDrawer, active: _index == 0),
          IdeasScreen(onOpenDrawer: _openDrawer),
        ],
      ),
    );
  }
}
