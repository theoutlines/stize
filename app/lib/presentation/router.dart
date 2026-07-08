import 'package:go_router/go_router.dart';

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
      builder: (context, state) {
        final stopId = state.pathParameters['stopId']!;
        final stopName = state.uri.queryParameters['name'];
        return StopScreen(stopId: stopId, initialStopName: stopName);
      },
    ),
    GoRoute(
      path: '/map',
      builder: (context, state) {
        final args = state.extra as MapScreenArgs;
        return MapScreen(
          stops: args.stops,
          center: args.center,
          centerLabel: args.centerLabel,
          title: args.title,
          polyline: args.polyline,
          extraMarkers: args.extraMarkers,
          lineNumber: args.lineNumber,
        );
      },
    ),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
  ],
);
