import 'package:go_router/go_router.dart';

import '../core/adaptive.dart';
import 'screens/about_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/city_screen.dart';
import 'screens/coverage_screen.dart';
import 'screens/root_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/linked_stop_screen.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const RootScreen()),
    GoRoute(
      path: '/stop/:stopId',
      pageBuilder: (context, state) {
        final stopId = state.pathParameters['stopId']!;
        final stopName = state.uri.queryParameters['name'];
        // A shared stop link opens the home map with that stop in its sheet
        // (mobile) or panel (desktop), the same surface as a tap on the map.
        return NoTransitionPage(
          key: state.pageKey,
          child: LinkedStopScreen(stopId: stopId, stopName: stopName),
        );
      },
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) =>
          adaptivePage(key: state.pageKey, child: const SettingsScreen()),
    ),
    GoRoute(
      path: '/about',
      pageBuilder: (context, state) =>
          adaptivePage(key: state.pageKey, child: const AboutScreen()),
    ),
    GoRoute(
      path: '/privacy',
      pageBuilder: (context, state) =>
          adaptivePage(key: state.pageKey, child: const PrivacyScreen()),
    ),
    // Coverage map (infographic) — reachable via the drawer entry, gated on the
    // remote `coverage_map_show` flag. Also a section of the root IndexedStack;
    // this standalone route lets it be deep-linked when enabled.
    GoRoute(
      path: '/coverage',
      pageBuilder: (context, state) =>
          adaptivePage(key: state.pageKey, child: const CoverageScreen()),
    ),
    // City section (transport analytics) — reachable via the menu entry, which
    // is gated on the remote `analytics_show` flag.
    GoRoute(
      path: '/analytics',
      pageBuilder: (context, state) =>
          adaptivePage(key: state.pageKey, child: const CityScreen()),
    ),
    GoRoute(
      path: '/analytics/:line',
      pageBuilder: (context, state) => adaptivePage(
        key: state.pageKey,
        child: CityLineScreen(line: state.pathParameters['line']!),
      ),
    ),
  ],
);
