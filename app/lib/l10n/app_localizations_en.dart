// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Stigla';

  @override
  String get navHome => 'Map';

  @override
  String get navMyStops => 'My Stops';

  @override
  String get navIdeas => 'Ideas';

  @override
  String get navAbout => 'About';

  @override
  String get ideasEmptyTitle => 'No ideas yet';

  @override
  String get ideasEmptySubtitle => 'Be the first to suggest something.';

  @override
  String get ideaInputHint => 'What should Stigla do better?';

  @override
  String get ideaSubmit => 'Suggest';

  @override
  String get ideaRateLimited =>
      'One new idea at a time — try again in a few minutes.';

  @override
  String ideaVotesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes',
      one: '1 vote',
      zero: 'No votes yet',
    );
    return '$_temp0';
  }

  @override
  String get ideaCommentsTitle => 'Comments';

  @override
  String get ideaCommentInputHint => 'Add a comment…';

  @override
  String get ideaCommentSubmit => 'Post';

  @override
  String get ideaCommentsEmpty => 'No comments yet.';

  @override
  String get myStopsEmptyTitle => 'No favorite stops yet';

  @override
  String get myStopsEmptySubtitle =>
      'Search for a stop, street, or line and add it here.';

  @override
  String get searchHint => 'Search stops, streets, or lines…';

  @override
  String get searchNoResults => 'Nothing found. Try a different spelling?';

  @override
  String get locationDenied =>
      'Location access is denied. Allow it in your browser or settings to see where you are.';

  @override
  String get locationServicesOff =>
      'Location services are off. Turn them on in your device settings.';

  @override
  String get locationTimeout =>
      'Couldn\'t get your location in time. Check your connection and try again.';

  @override
  String get locationUnavailable =>
      'Your location is unavailable right now. Try again in a moment.';

  @override
  String get nearbyStopsTitle => 'Nearby stops';

  @override
  String get nearbyStopsEmpty =>
      'Turn on location, or search for a stop, street, or line above.';

  @override
  String get mapZoomInForVehicles => 'Zoom in to see live transport';

  @override
  String get vehicleScheduled => 'By schedule — not a live position';

  @override
  String get arrivalExpected => 'Expected';

  @override
  String get vehicleLost => 'Vehicle no longer tracked';

  @override
  String get followingVehicle => 'Following';

  @override
  String get noLiveVehiclesOnMap =>
      'No live-tracked vehicles to map right now — see the arrivals below.';

  @override
  String get nearbySearchHint => 'Filter lines nearby…';

  @override
  String nearbyDistanceMeters(int meters) {
    return '$meters m';
  }

  @override
  String get nearbyNeedsLocationTitle => 'See what\'s nearby';

  @override
  String get nearbyNeedsLocationSubtitle =>
      'Turn on location to list the lines you can catch around you.';

  @override
  String get nearbyEnableLocation => 'Use my location';

  @override
  String get nearbyLoading => 'Finding lines around you…';

  @override
  String get nearbyEmptyTitle => 'No stops nearby';

  @override
  String get nearbyEmptySubtitle =>
      'There are no stops within walking distance of you right now.';

  @override
  String get stopUpdatedJustNow => 'Updated just now';

  @override
  String stopUpdatedSecondsAgo(int seconds) {
    return 'Updated ${seconds}s ago';
  }

  @override
  String stopUpdatedMinutesAgo(int minutes) {
    return 'Updated $minutes min ago';
  }

  @override
  String arrivalEtaMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get arrivalEtaNow => 'Now';

  @override
  String get arrivalScheduled => 'Scheduled';

  @override
  String arrivalStopsAway(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops away',
      one: '1 stop away',
      zero: 'here',
    );
    return '$_temp0';
  }

  @override
  String get vehicleMoving => 'On the move';

  @override
  String get vehicleStuck => 'Looks stopped';

  @override
  String get vehicleNextStop => 'Next stop';

  @override
  String get vehicleUpcomingStops => 'Rest of the route';

  @override
  String get vehicleYourStop => 'your stop';

  @override
  String get vehicleEtaApprox => 'Arrival times are approximate';

  @override
  String get vehicleShowRoute => 'Show route on map';

  @override
  String vehicleEtaMinutesApprox(int minutes) {
    return '≈ $minutes min';
  }

  @override
  String get emptyArrivalsTitle => 'It\'s quiet here right now';

  @override
  String get emptyArrivalsSubtitle => 'Something should be along shortly.';

  @override
  String get noNetworkTitle => 'Looks like the connection dropped';

  @override
  String get noNetworkSubtitle =>
      'Check your connection and pull down to try again.';

  @override
  String get loadingArrivals => 'Checking what\'s on the way…';

  @override
  String get serviceKilledTitle => 'We\'re taking a short break';

  @override
  String get serviceKilledSubtitle => 'Back soon.';

  @override
  String get liveUnavailableBanner =>
      'Live data temporarily unavailable — timetable';

  @override
  String get unknownStopTitle => 'Can\'t find that stop';

  @override
  String get unknownStopSubtitle =>
      'It may have been renamed or removed from the schedule.';

  @override
  String get retry => 'Try again';

  @override
  String get addToFavorites => 'Add to My Stops';

  @override
  String get removeFromFavorites => 'Remove from My Stops';

  @override
  String get pinnedRenameTitle => 'Custom name';

  @override
  String get pinnedCustomNameHint => 'e.g. Home, Work';

  @override
  String get pinnedUseDefaultName => 'Default name';

  @override
  String get pinLineTooltip => 'Pin line';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'Match system';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get vehicleModeOnDemand => 'On demand';

  @override
  String get vehicleModeAll => 'All transport';

  @override
  String get vehicleModeTooltip => 'Transport on the map';

  @override
  String vehicleModeSwitched(String mode) {
    return 'Transport on the map: $mode';
  }

  @override
  String get aboutTitle => 'About Stigla';

  @override
  String aboutRouteData(String date) {
    return 'Route data: $date';
  }

  @override
  String get aboutDisclaimer =>
      'Unofficial app. Not affiliated with JKP Upravljanje javnim prevozom Beograd.';

  @override
  String get aboutDescription =>
      'Stigla shows real-time Belgrade public transport arrivals. Built for personal use.';

  @override
  String get lineFilterAll => 'All lines';

  @override
  String get alertUpcomingLabel => 'Upcoming change';

  @override
  String get alertActiveLabel => 'Route change';

  @override
  String get alertReadMore => 'Read more';

  @override
  String get alertsBannerTitle => 'Transport changes';

  @override
  String get vehicleTypeBus => 'Bus';

  @override
  String get vehicleTypeTram => 'Tram';

  @override
  String get vehicleTypeTrolleybus => 'Trolleybus';

  @override
  String fleetAgeYears(int years) {
    return '$years yr';
  }

  @override
  String fleetVehicleNumber(String number) {
    return '#$number';
  }

  @override
  String get fleetSortByTime => 'By time';

  @override
  String get fleetSortByComfort => 'By comfort';

  @override
  String get fleetUnknownModel => 'Model unknown';

  @override
  String get fleetSectionComfort => 'Comfort';

  @override
  String get fleetSectionAmenities => 'On board';

  @override
  String get fleetSectionDetails => 'Details';

  @override
  String get fleetAc => 'Air conditioning';

  @override
  String get fleetNoAc => 'No air conditioning';

  @override
  String get fleetLowFloor => 'Low floor';

  @override
  String get fleetHighFloor => 'Steps at the door';

  @override
  String get fleetArticulated => 'Articulated (bendy)';

  @override
  String get fleetUsb => 'USB charging';

  @override
  String get fleetElectric => 'Electric';

  @override
  String get fleetHybrid => 'Hybrid';

  @override
  String get fleetCng => 'Runs on gas (CNG)';

  @override
  String get fleetTrolley => 'Trolleybus';

  @override
  String get fleetTram => 'Tram';

  @override
  String get fleetDiesel => 'Diesel';

  @override
  String get fleetAge => 'Age';

  @override
  String fleetAgeApprox(int years, int from, int to) {
    return '~$years yr (built $from–$to)';
  }

  @override
  String fleetCapacity(int count) {
    return 'Holds ~$count';
  }

  @override
  String fleetLength(String meters) {
    return '$meters m long';
  }

  @override
  String fleetOperator(String name) {
    return 'Operator: $name';
  }

  @override
  String fleetManufacturer(String value) {
    return 'Manufacturer: $value';
  }

  @override
  String get fleetComfortRetro => 'retro';

  @override
  String get fleetComfortOk => 'ok';

  @override
  String get fleetComfortComfy => 'comfort';

  @override
  String get fleetApproxNote =>
      '“~” marks values estimated for this operator, not confirmed for this exact vehicle.';

  @override
  String get navCoverage => 'Coverage';

  @override
  String get coverageFilterAll => 'All';

  @override
  String get coverageLegendTitle => 'Transit density';

  @override
  String get coverageLegendLow => 'rarer';

  @override
  String get coverageLegendHigh => 'busier';

  @override
  String get coverageUnavailable => 'Coverage map is unavailable right now.';
}
