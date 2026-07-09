import 'package:go_router/go_router.dart';

import '../core/adaptive.dart';
import 'screens/about_screen.dart';
import 'screens/map_screen.dart';
import 'screens/map_screen_args.dart';
import 'screens/root_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stop_screen.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const RootScreen()),
    GoRoute(
      path: '/stop/:stopId',
      pageBuilder: (context, state) {
        final stopId = state.pathParameters['stopId']!;
        final stopName = state.uri.queryParameters['name'];
        return adaptivePage(
          key: state.pageKey,
          child: StopScreen(stopId: stopId, initialStopName: stopName),
        );
      },
    ),
    GoRoute(
      path: '/map',
      pageBuilder: (context, state) {
        final args = state.extra as MapScreenArgs;
        return adaptivePage(
          key: state.pageKey,
          child: MapScreen(
            stops: args.stops,
            center: args.center,
            centerLabel: args.centerLabel,
            title: args.title,
            polyline: args.polyline,
            lineNumber: args.lineNumber,
          ),
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
  ],
);
