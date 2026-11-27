import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stize/core/context_slot.dart';
import 'package:stize/domain/models/arrival.dart';
import 'package:stize/domain/repositories/nearby_arrivals_repository.dart';
import 'package:stize/domain/models/nearby_arrival.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/widgets/nearby_sheet.dart';
import 'package:stize/presentation/widgets/nearby_view.dart';

// Every mobile bottom sheet must cap at `large` (owner R2 #4 / R3 #3): dragged
// to the top it stops at kSheetLarge, leaving a strip of map — never fullscreen.
// These tests prove the cap deterministically for each sheet path.

class _EmptyNearby implements NearbyArrivalsRepository {
  @override
  Future<NearbyResult> nearby({
    required double lat,
    required double lon,
    double radiusMeters = 500,
  }) async => const NearbyResult(groups: [], serviceStatus: ServiceStatus.ok);
}

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    );

DraggableScrollableSheet _theSheet(WidgetTester tester) => tester
    .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));

void main() {
  testWidgets('detent constants: large is not fullscreen', (_) async {
    expect(kSheetLarge, lessThan(1.0));
    expect(kSheetDetents.last, kSheetLarge);
  });

  testWidgets('Nearby sheet caps at large (maxChildSize + snap)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        NearbySheet(
          userLocation: ll.LatLng(44.8, 20.5),
          locationDenied: false,
          active: true,
          onEnableLocation: () {},
        ),
        overrides: [
          nearbyArrivalsRepositoryProvider.overrideWithValue(_EmptyNearby()),
        ],
      ),
    );
    await tester.pump();
    final sheet = _theSheet(tester);
    expect(sheet.maxChildSize, kSheetLarge);
    expect(sheet.snapSizes, contains(kSheetLarge));
    expect(sheet.snapSizes!.every((s) => s <= kSheetLarge), isTrue);
    await tester.pumpWidget(const SizedBox()); // cancel the 30s timer
  });

  testWidgets('full Nearby sheet: a slow pull down stays, a flick collapses', (
    tester,
  ) async {
    final ctl = DraggableScrollableController();
    await tester.pumpWidget(
      _app(
        NearbySheet(
          controller: ctl,
          oneScroll: true,
          userLocation: ll.LatLng(44.8, 20.5),
          locationDenied: false,
          active: true,
          onEnableLocation: () {},
        ),
        overrides: [
          nearbyArrivalsRepositoryProvider.overrideWithValue(_EmptyNearby()),
        ],
      ),
    );
    await tester.pump();
    final list = find.byType(Scrollable).last;
    // Raise the sheet to its top by dragging the list.
    final before = tester.state(find.byType(NearbyView));
    await tester.drag(list, const Offset(0, -900));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(ctl.size, closeTo(kSheetLarge, 0.01));
    // The list keeps its state when it takes its own scroll at the top (it
    // used to be rebuilt and refetch, flashing "Finding lines").
    expect(identical(tester.state(find.byType(NearbyView)), before), isTrue);
    // A slow pull at the list's top overscrolls the list, not the sheet.
    final at = tester.getCenter(find.byType(DraggableScrollableSheet));
    final g = await tester.startGesture(at);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(ctl.size, closeTo(kSheetLarge, 0.01));
    await g.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(ctl.size, closeTo(kSheetLarge, 0.01));
    // A quick flick down collapses it.
    await tester.flingFrom(at, const Offset(0, 60), 1500);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(ctl.size, lessThan(kSheetLarge - 0.1));
    await tester.pumpWidget(const SizedBox());
  });
}
