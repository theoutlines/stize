// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Stiže';

  @override
  String get navHome => 'Map';

  @override
  String get navMyStops => 'My Stops';

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
  String get searchMoreResults => 'More results';

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
  String get vehicleScheduled => 'By schedule — not a live position';

  @override
  String get vehicleLost => 'Vehicle no longer tracked';

  @override
  String get followingVehicle => 'Following';


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
  String get arrivalEtaMinutesUnit => 'min';

  @override
  String get arrivalEtaNow => 'Now';

  @override
  String arrivalStopsAway(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops away',
      one: '1 stop away',
      zero: 'At the stop',
    );
    return '$_temp0';
  }









  @override
  String get contextNearbyTitle => 'Nearby';

  @override
  String get backToVehicle => 'Back to vehicle';

  @override
  String get backTo => 'Back to';


  @override
  String get routeUnavailable => 'Route unavailable for this line';

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
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get vehicleModeOnDemand => 'On demand';

  @override
  String get vehicleModeAll => 'All transport';

  @override
  String get vehicleModeHint => 'Live transport';

  @override
  String get vehicleModeTooltip => 'Transport on the map';

  @override
  String vehicleModeSwitched(String mode) {
    return 'Transport on the map: $mode';
  }

  @override
  String get aboutTitle => 'About Stiže';

  @override
  String aboutRouteData(String date) {
    return 'Route data: $date';
  }

  @override
  String get aboutDisclaimer =>
      'Unofficial app. Not affiliated with JKP Upravljanje javnim prevozom Beograd.';

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
  String fleetVehicleNumber(String number) {
    return '#$number';
  }

  @override
  String get fleetUnknownModel => 'Model unknown';


  @override
  String get fleetAc => 'Air conditioning';







  @override
  String get fleetHybrid => 'Hybrid';











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
  String get drawerShareFeedback => 'Share feedback';

  @override
  String get drawerFeedbackSheetTitle => 'Feedback';


  @override
  String get feedbackWriteToMeSubtitle =>
      'Send a message: bugs, ideas, anything.';



  @override
  String get feedbackFormTitle => 'Write to me';

  @override
  String get feedbackMessageLabel => 'Your message';

  @override
  String get feedbackMessageHint => 'A bug, an idea, a kind word…';

  @override
  String get feedbackContactLabel => 'Contact (optional)';

  @override
  String get feedbackContactHint => 'Email or Telegram, if you want a reply';

  @override
  String get feedbackSend => 'Send';

  @override
  String get feedbackSent => 'Thanks — your message was sent.';

  @override
  String get feedbackErrorGeneric => 'Couldn\'t send. Please try again later.';

  @override
  String get feedbackErrorRateLimited =>
      'Please wait a moment before sending more.';

  @override
  String get feedbackEmptyValidation => 'Write a message first.';

  @override
  String get drawerLicenses => 'Open source licenses';

  @override
  String get drawerPrivacy => 'Privacy policy';

  @override
  String get licensesLegalese =>
      'Stiže is free software under the AGPL-3.0 license.';

  @override
  String get privacyTitle => 'Privacy policy';

  @override
  String get privacyIntro =>
      'Stiže is private by default. Here\'s exactly what it does with data, in plain language.';

  @override
  String get privacyLocationTitle => 'Your location';

  @override
  String get privacyLocationBody =>
      'When you ask to see nearby stops and vehicles, your device\'s location is sent to our API with that request to find what\'s around you. It is used only to answer that request and is never stored on our servers.';

  @override
  String get privacyAnalyticsTitle => 'Anonymous usage';

  @override
  String get privacyAnalyticsBody =>
      'The app may record anonymous usage events (for example, that a stop was opened) to understand which features are used. These carry no identifiers and no accounts, and cannot be traced back to you.';

  @override
  String get privacyTrackersTitle => 'No ads, no trackers';

  @override
  String get privacyTrackersBody =>
      'Stiže shows no ads and includes no third-party advertising or tracking SDKs.';

  @override
  String get privacyFeedbackTitle => 'Feedback you send';

  @override
  String get privacyFeedbackBody =>
      'If you send feedback, your message — and the optional contact you provide — are stored so we can read it and reply to you. Nothing else is collected with it.';

  @override
  String get privacyServicesTitle => 'Services the app loads from';

  @override
  String get privacyServicesBody =>
      'Like any website, the app loads some parts from other services, which see your IP address as part of the request: map tiles for the area you view come from MapTiler, fonts and parts of the app engine from Google (gstatic.com), and the app and its API are served by Cloudflare. None of them receive your location from us or any account details.';

  @override
  String get privacyOpenSourceTitle => 'Open source';

  @override
  String get privacyOpenSourceBody =>
      'Stiže\'s code is open source under the AGPL-3.0 license, so anyone can inspect exactly how it works.';

  @override
  String jamStopBannerTitle(String line) {
    return 'Trams $line have been stopped longer than usual — possible delay';
  }

  @override
  String jamSubstitutionNotice(String line) {
    return 'Buses are running instead of trams on line $line';
  }

  @override
  String get jamModeTooltip => 'Show stalled segments';

  @override
  String jamNearbyDelay(String line) {
    return 'Possible delay on line $line';
  }

  @override
  String get jamAffectedStopsTitle => 'Affected stops';

  @override
  String get jamFollowAhead => 'Possible delay ahead on the route';


  @override
  String get arrivalTerminus => 'Terminus';

  @override
  String get stopMore => 'More';

  @override
  String get stopReportProblem => 'Report a problem';

  @override
  String get stopInMyStops => 'In My Stops';

  @override
  String get stopReportTitle => 'What’s wrong?';

  @override
  String get stopReportNotHere => 'The stop isn’t here or it’s elsewhere';

  @override
  String get stopReportWrongType => 'Wrong type (bus, tram, trolleybus)';

  @override
  String get stopReportWrongLines => 'Wrong lines';

  @override
  String get stopReportArrivalsWrong => 'Arrivals don’t match reality';

  @override
  String get stopReportWrongName => 'Wrong name';

  @override
  String get stopReportOther => 'Something else';

  @override
  String get stopReportOtherLabel => 'Tell us what’s wrong';

  @override
  String get stopReportOtherHint => 'Needed for “Something else”';

  @override
  String get stopReportPrivacy =>
      'We get the stop and its lines. Not your location.';

  @override
  String get stopReportSend => 'Send';

  @override
  String get stopReportSentTitle => 'Thanks, got it';

  @override
  String stopReportSentBody(String what, String stop) {
    return 'We’ll check “$what” at $stop and fix the data. You don’t need to do anything else.';
  }

  @override
  String get stopReportAlreadyTitle => 'Already sent today';

  @override
  String stopReportAlreadyBody(String what) {
    return 'You told us about “$what” at this stop today. One report is enough: we’ll check it.';
  }

  @override
  String get stopReportBack => 'Back to the stop';

  @override
  String get stopReportTooFast =>
      'Please wait a minute before sending another report.';

  @override
  String get stopReportFailed =>
      'Couldn’t send. Check the connection and try again.';

  @override
  String get aboutDataSource =>
      'Stops, lines and timetables: open data of the City of Belgrade (Secretariat for Public Transport), published on data.gov.rs under the Serbian open data licence. We repackage them for the app. Map: MapTiler, OpenStreetMap contributors.';

  @override
  String get menuSupport => 'Support Stiže';

  @override
  String get menuClose => 'Close menu';

  @override
  String get settingsAuto => 'Auto';

  @override
  String get settingsAutoHint =>
      'Auto follows your phone. Transport on the map is switched with the layers button on the map.';

  @override
  String get guideTitle => 'Belgrade guide';

  @override
  String get guideFree => 'City transport is free: buses, trams, trolleybuses';

  @override
  String get guideGettingAround => 'Getting around';

  @override
  String get guideFromAirport => 'From the airport';

  @override
  String get guideFromAirportSub => 'Lines 72, A1, 600, 607 · 72N at night';

  @override
  String get guideFromBusStation => 'From the bus station';

  @override
  String get guideFromBusStationSub =>
      'Beogradska autobuska stanica, New Belgrade';

  @override
  String get guideFromRailStation => 'From the railway station';

  @override
  String get guideFromRailStationSub => 'Beograd Centar (Prokop)';

  @override
  String get guideReadStop => 'How to read a stop';

  @override
  String get guideReadStopSub => 'Live minutes and timetable times';

  @override
  String get guideReadStopLive =>
      'Big minutes are live: the vehicle is on its way and we see it on GPS.';

  @override
  String get guideReadStopScheduled =>
      'A time of day is from the timetable: no live signal for that trip yet.';

  @override
  String get guideReadStopStar => 'Tap the star to keep a stop in My stops.';

  @override
  String get guideReadStopNight => 'Lines ending in N run at night.';

  @override
  String get guidePlaces => 'Places people ask for';

  @override
  String get guidePlacesSub => 'Fortress, squares, stations, Ada';

  @override
  String get guideNowLabel => 'Right now';

  @override
  String get guideExpoTitle => 'Expo 2027 in Belgrade';

  @override
  String get guideExpoDays => 'days to opening';

  @override
  String get guideExpoSub =>
      '15 May to 15 August 2027. We add the Expo lines as soon as the city announces them.';

  @override
  String get guideNightTitle => 'Night lines are running';

  @override
  String get guideNightSub =>
      'After midnight the night lines take over. Their numbers end in N.';

  @override
  String get guideStripNight => 'Night lines are running';

  @override
  String get guideStripNightSub => 'What runs after midnight';

  @override
  String get guideStripNew => 'New to Belgrade? Open the guide';

  @override
  String get guideStripNewSub => 'Free rides, airport, night lines';

  @override
  String get guideStripAirport => 'You\'re at the airport';

  @override
  String get guideStripAirportSub => 'Into the city: 72, A1, 600';

  @override
  String get guideStripBusStation => 'You\'re at the bus station';

  @override
  String get guideStripBusStationSub =>
      'City lines leave from the stops by the exit';

  @override
  String get guideStripRailStation => 'You\'re at Beograd Centar station';

  @override
  String get guideStripRailStationSub => 'City lines: 34, 36, 600';

  @override
  String arrivalThenTo(String place) {
    return 'Then to $place';
  }

  @override
  String get locateMeTooltip => 'Show where I am';

  @override
  String get nearbyAroundYou => 'Around you';

  @override
  String get cityTitle => 'City';

  @override
  String get cityHeadline => 'How Belgrade transport runs';

  @override
  String get citySubtitle => 'From arrivals our users saw';

  @override
  String get cityKpiDelay => 'Average delay';

  @override
  String get cityKpiInterval => 'Typical interval';

  @override
  String get cityKpiLines => 'Lines seen';

  @override
  String get cityKpiArrivals => 'Arrivals seen';

  @override
  String cityMin(int n) {
    return '$n min';
  }

  @override
  String get cityOnTime => 'on time';

  @override
  String cityLateBy(int n) {
    return '$n min late';
  }

  @override
  String cityEarlyBy(int n) {
    return '$n min early';
  }

  @override
  String get cityHeatTitle => 'When it runs late';

  @override
  String get cityHeatSubtitle => 'Average delay by weekday and hour';

  @override
  String get cityLegendLow => 'on time';

  @override
  String get cityLegendHigh => 'often late';

  @override
  String cityHeatWorst(String day, int hour, int min) {
    return 'Worst: $day at $hour:00, about $min min late.';
  }

  @override
  String cityHeatCell(String day, int hour, int next) {
    return '$day $hour:00–$next:00';
  }

  @override
  String cityHeatCellCount(int n) {
    return '$n arrivals';
  }

  @override
  String get cityHeatFew => 'too few arrivals';

  @override
  String get cityLinesTitle => 'Lines';

  @override
  String get cityLinesSubtitle => 'Size: arrivals seen · number: average delay';

  @override
  String cityLinesSummary(String best, String worst) {
    return '$best is the most punctual line. $worst runs the latest.';
  }

  @override
  String get cityLegendBest => 'best';

  @override
  String get cityLegendWorst => 'worst';

  @override
  String get cityLegendThin => 'too few arrivals to judge';

  @override
  String get cityIntervalsTitle => 'Longest real intervals';

  @override
  String get cityIntervalsSubtitle => 'Evenings 21:00 to 01:00, average wait';

  @override
  String get cityNote =>
      'We only see stops people open, at the hours they open them. Lines with too few arrivals are not ranked.';

  @override
  String get cityEmptyTitle => 'Not enough arrivals yet';

  @override
  String cityEmptyBody(int min) {
    return 'Stats appear once we have seen at least $min arrivals.';
  }

  @override
  String get cityLineUsual => 'Usually at this hour';

  @override
  String cityLineEvery(int n) {
    return 'every $n min';
  }

  @override
  String get cityLineHeatSubtitle => 'This line, by weekday and hour';

  @override
  String cityLineThinBody(int n, int min) {
    return 'We have seen $n arrivals of this line. Stats appear after $min.';
  }

  @override
  String get cityLineNoHour => 'no data for this hour';

  @override
  String cityLinesBestOnly(String best) {
    return '$best is the most punctual line; none of the busy lines runs notably late.';
  }

  @override
  String arrivalNextList(String times) {
    return 'next $times min';
  }

  @override
  String get arrivalStartsHere => 'Starts here';

  @override
  String get arrivalByTimetable => 'By timetable';

  @override
  String followStopsTo(int count, String stop) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops to $stop',
      one: '1 stop to $stop',
    );
    return '$_temp0';
  }

  @override
  String followAtStop(String stop) {
    return 'At $stop';
  }

  @override
  String followNextStop(String stop) {
    return 'Next: $stop';
  }

  @override
  String followStuck(int minutes) {
    return 'Stuck · $minutes min';
  }

  @override
  String get followYourStop => 'Your stop';

  @override
  String fleetChipAge(int years) {
    return '$years yr';
  }

  @override
  String fleetChipCapacity(int count) {
    return '~$count people';
  }

  @override
  String fleetChipComfort(String word) {
    return 'Comfort: $word';
  }

  @override
  String get fleetChipSteps => 'Steps';

  @override
  String get fleetChipLowFloor => 'Low floor';

  @override
  String fleetMadeBy(String value) {
    return 'Made by $value';
  }

  @override
  String fleetOperatorShort(String name) {
    return 'Operator $name';
  }

  @override
  String fleetPhotoShort(String author, String license) {
    return 'Photo: $author, $license';
  }

  @override
  String get close => 'Close';

  @override
  String get fleetChipArticulated => 'Articulated';

  @override
  String get fleetChipAc => 'A/C';

  @override
  String get fleetChipNoAc => 'No A/C';

  @override
  String get nearbyThisPoint => 'Around this point';
}
