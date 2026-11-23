import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vehicle_map_mode.dart';
import '../../data/analytics/event_logger.dart';
import '../providers/providers.dart';
import '../widgets/app_menu.dart';
import 'coverage_screen.dart';
import 'home_map_screen.dart';

class RootScreen extends ConsumerStatefulWidget {
  const RootScreen({super.key});

  @override
  ConsumerState<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends ConsumerState<RootScreen> {
  int _index = 0;
  bool _loggedAppOpen = false;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: keeps the offline stop/line reference fresh without
    // blocking startup. Safe to ignore failures — the live API is always
    // tried first anyway.
    unawaited(ref.read(gtfsOfflineCacheProvider).refreshIfStale());
  }

  /// Emit the once-per-launch `app_open` — but only after config resolves (so the
  /// gate is known and the resolved vehicle-map mode is meaningful). `mode` is
  /// the current map mode; `locale_class` is the coarse class of the *system*
  /// locale (a local-vs-tourist proxy), read straight from the platform so a
  /// user's in-app language override doesn't mask it.
  void _maybeLogAppOpen(bool analyticsEnabled) {
    if (_loggedAppOpen || !analyticsEnabled) return;
    _loggedAppOpen = true;
    final mode = ref.read(vehicleMapModeProvider);
    ref
        .read(eventLoggerProvider)
        .log(
          Ev.appOpen,
          props: {
            'mode': mode == VehicleMapMode.aquarium
                ? Ev.modeAquarium
                : Ev.modeOnDemand,
            'locale_class': localeClassOf(
              WidgetsBinding.instance.platformDispatcher.locale.languageCode,
            ),
          },
        );
  }

  /// Opens the menu popover. Called from the map's round menu button, the
  /// desktop panel's burger, the coverage screen, and the menu-button twin drawn
  /// over an open stop sheet — so the menu opens in one tap with the stop kept.
  void _openDrawer() {
    final sectionCount = ref.read(coverageEnabledProvider) ? 2 : 1;
    showAppMenu(
      context,
      topInset: MediaQuery.paddingOf(context).top,
      currentIndex: _index.clamp(0, sectionCount - 1),
      onSelectSection: (i) => setState(() => _index = i),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The coverage tab is a third section, but only when its remote flag is on —
    // so a dormant feature never builds its (map-backed) screen.
    final coverageEnabled = ref.watch(coverageEnabledProvider);
    // Wire the analytics gate to the `product_analytics` flag (sets the logger's
    // enabled state once config resolves) and emit app_open the first time it's
    // known to be on. With the flag off this stays a pure no-op — zero requests.
    final analyticsEnabled = ref.watch(eventLoggerGateProvider);
    _maybeLogAppOpen(analyticsEnabled);
    final sectionCount = coverageEnabled ? 2 : 1;
    // If the flag flips off while coverage is showing, fall back to the map.
    final index = _index.clamp(0, sectionCount - 1);

    // The home map and the Coverage tab are each a MapLibreMap; both stay mounted
    // in the IndexedStack (instant switching, all state preserved). On web a map
    // whose container is already sized when created wouldn't kick its initial
    // render — that's handled in web/index.html (forced repaint until the map
    // settles), so two maps coexist there too.
    final sections = <Widget>[
      // `active` lets the map stop its continuous rendering when it's not the
      // visible section (iOS-web thermal fix).
      HomeMapScreen(onOpenDrawer: _openDrawer, active: index == 0),
      if (coverageEnabled) CoverageScreen(onOpenDrawer: _openDrawer),
    ];

    // The section pages switch inside one Scaffold; each opens the menu popover
    // through [_openDrawer].
    return Scaffold(
      body: IndexedStack(index: index, children: sections),
    );
  }
}
