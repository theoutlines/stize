import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:stigla/core/map_support.dart';
import 'package:stigla/data/location/location_service.dart';
import 'package:stigla/domain/models/app_config.dart';
import 'package:stigla/domain/models/geocode_result.dart';
import 'package:stigla/domain/models/line_info.dart';
import 'package:stigla/domain/models/stop.dart';
import 'package:stigla/domain/repositories/geocode_repository.dart';
import 'package:stigla/domain/repositories/lines_repository.dart';
import 'package:stigla/domain/repositories/stops_repository.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/screens/home_map_screen.dart';
import 'package:stigla/presentation/widgets/context_shell.dart';

/// Location permanently denied → the map never starts a stream (hermetic).
class _DeniedLocation extends LocationService {
  @override
  Future<bool> isPermissionGranted() async => false;
  @override
  Future<Position?> lastKnownIfGranted() async => null;
}

// Empty search repos so a typed query doesn't hit the network (which throws
// under flutter_test). The re-expand happens on keystroke, before any fetch.
class _EmptyStops implements StopsRepository {
  @override
  Future<List<Stop>> search(String query) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _EmptyLines implements LinesRepository {
  @override
  Future<List<LineInfo>> search(String query) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _EmptyGeocode implements GeocodeRepository {
  @override
  Future<List<GeocodeResult>> search(String query) async => const [];
}

Widget _host({required Size size}) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWith(
        (ref) async => const AppConfig(version: 'test', flags: {
          'context_panel': true,
          'nearby_list': true,
          'vehicles_on_demand': true,
        }),
      ),
      locationServiceProvider.overrideWithValue(_DeniedLocation()),
      favoriteStopLocationsProvider.overrideWith((ref) async => const <Stop>[]),
      stopsRepositoryProvider.overrideWithValue(_EmptyStops()),
      linesRepositoryProvider.overrideWithValue(_EmptyLines()),
      geocodeRepositoryProvider.overrideWithValue(_EmptyGeocode()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const HomeMapScreen(),
      ),
    ),
  );
}

Offset _bodyOffset(WidgetTester tester) =>
    tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset;

Finder _tabChevron(IconData icon) => find.descendant(
      of: find.byType(PanelCollapseTab),
      matching: find.byIcon(icon),
    );

void main() {
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets(
      'collapse tab toggles panel visibility and flips the chevron; '
      'search stays visible in both states', (tester) async {
    await tester.pumpWidget(_host(size: const Size(1200, 800)));
    await tester.pump();
    await tester.pump();

    // Default: expanded. Panel body in place (offset zero), chevron points left,
    // the persistent global search is present.
    expect(find.byType(PanelCollapseTab), findsOneWidget);
    expect(_bodyOffset(tester), Offset.zero);
    expect(_tabChevron(Icons.chevron_left), findsOneWidget);
    expect(_tabChevron(Icons.chevron_right), findsNothing);
    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);

    // Collapse.
    await tester.tap(find.byType(PanelCollapseTab));
    await tester.pumpAndSettle();

    // Body slid fully off the left edge; chevron flipped to ►…
    expect(_bodyOffset(tester), const Offset(-1.3, 0));
    expect(_tabChevron(Icons.chevron_right), findsOneWidget);
    expect(_tabChevron(Icons.chevron_left), findsNothing);
    // …and the global search is STILL visible (owner A#6), with a burger to
    // reach the drawer while collapsed.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsWidgets);

    // Expand again → back to the previous state.
    await tester.tap(find.byType(PanelCollapseTab));
    await tester.pumpAndSettle();
    expect(_bodyOffset(tester), Offset.zero);
    expect(_tabChevron(Icons.chevron_left), findsOneWidget);
  });

  testWidgets('entering a context (search) while collapsed re-expands the panel',
      (tester) async {
    await tester.pumpWidget(_host(size: const Size(1200, 800)));
    await tester.pump();
    await tester.pump();

    // Collapse first.
    await tester.tap(find.byType(PanelCollapseTab));
    await tester.pumpAndSettle();
    expect(_bodyOffset(tester), const Offset(-1.3, 0));
    expect(_tabChevron(Icons.chevron_right), findsOneWidget);

    // Start a search — a context entry (owner A#4). The results render in the
    // panel body, so this re-expands the panel automatically.
    await tester.enterText(find.byType(TextField), 'batutova');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(_bodyOffset(tester), Offset.zero); // back in place
    expect(_tabChevron(Icons.chevron_left), findsOneWidget);
  });
}
