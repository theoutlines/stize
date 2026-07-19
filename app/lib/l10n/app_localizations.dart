import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_sr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
    Locale('sr'),
  ];

  /// App name, shown in title bars and the OS app switcher
  ///
  /// In en, this message translates to:
  /// **'Stigla'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navHome;

  /// No description provided for @navMyStops.
  ///
  /// In en, this message translates to:
  /// **'My Stops'**
  String get navMyStops;

  /// No description provided for @navIdeas.
  ///
  /// In en, this message translates to:
  /// **'Ideas'**
  String get navIdeas;

  /// No description provided for @navAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get navAbout;

  /// No description provided for @ideasEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No ideas yet'**
  String get ideasEmptyTitle;

  /// No description provided for @ideasEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Be the first to suggest something.'**
  String get ideasEmptySubtitle;

  /// No description provided for @ideaInputHint.
  ///
  /// In en, this message translates to:
  /// **'What should Stigla do better?'**
  String get ideaInputHint;

  /// No description provided for @ideaSubmit.
  ///
  /// In en, this message translates to:
  /// **'Suggest'**
  String get ideaSubmit;

  /// No description provided for @ideaRateLimited.
  ///
  /// In en, this message translates to:
  /// **'One new idea at a time — try again in a few minutes.'**
  String get ideaRateLimited;

  /// No description provided for @ideaVotesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No votes yet} =1{1 vote} other{{count} votes}}'**
  String ideaVotesCount(int count);

  /// No description provided for @ideaCommentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get ideaCommentsTitle;

  /// No description provided for @ideaCommentInputHint.
  ///
  /// In en, this message translates to:
  /// **'Add a comment…'**
  String get ideaCommentInputHint;

  /// No description provided for @ideaCommentSubmit.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get ideaCommentSubmit;

  /// No description provided for @ideaCommentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No comments yet.'**
  String get ideaCommentsEmpty;

  /// No description provided for @myStopsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No favorite stops yet'**
  String get myStopsEmptyTitle;

  /// No description provided for @myStopsEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Search for a stop, street, or line and add it here.'**
  String get myStopsEmptySubtitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search stops, streets, or lines…'**
  String get searchHint;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing found. Try a different spelling?'**
  String get searchNoResults;

  /// No description provided for @locationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location access is denied. Allow it in your browser or settings to see where you are.'**
  String get locationDenied;

  /// No description provided for @locationServicesOff.
  ///
  /// In en, this message translates to:
  /// **'Location services are off. Turn them on in your device settings.'**
  String get locationServicesOff;

  /// No description provided for @locationTimeout.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get your location in time. Check your connection and try again.'**
  String get locationTimeout;

  /// No description provided for @locationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Your location is unavailable right now. Try again in a moment.'**
  String get locationUnavailable;

  /// No description provided for @nearbyStopsTitle.
  ///
  /// In en, this message translates to:
  /// **'Nearby stops'**
  String get nearbyStopsTitle;

  /// No description provided for @nearbyStopsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Turn on location, or search for a stop, street, or line above.'**
  String get nearbyStopsEmpty;

  /// No description provided for @mapZoomInForVehicles.
  ///
  /// In en, this message translates to:
  /// **'Zoom in to see live transport'**
  String get mapZoomInForVehicles;

  /// No description provided for @vehicleScheduled.
  ///
  /// In en, this message translates to:
  /// **'By schedule — not a live position'**
  String get vehicleScheduled;

  /// Row with a valid ETA but no live GPS position yet (placeholder vehicle)
  ///
  /// In en, this message translates to:
  /// **'Expected'**
  String get arrivalExpected;

  /// Shown when a followed vehicle drops out of the live feed
  ///
  /// In en, this message translates to:
  /// **'Vehicle no longer tracked'**
  String get vehicleLost;

  /// Follow-bar label shown while following a vehicle before its route terminals have loaded.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get followingVehicle;

  /// No description provided for @noLiveVehiclesOnMap.
  ///
  /// In en, this message translates to:
  /// **'No live-tracked vehicles to map right now — see the arrivals below.'**
  String get noLiveVehiclesOnMap;

  /// No description provided for @nearbySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Filter lines nearby…'**
  String get nearbySearchHint;

  /// No description provided for @nearbyDistanceMeters.
  ///
  /// In en, this message translates to:
  /// **'{meters} m'**
  String nearbyDistanceMeters(int meters);

  /// No description provided for @nearbyNeedsLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'See what\'s nearby'**
  String get nearbyNeedsLocationTitle;

  /// No description provided for @nearbyNeedsLocationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on location to list the lines you can catch around you.'**
  String get nearbyNeedsLocationSubtitle;

  /// No description provided for @nearbyEnableLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get nearbyEnableLocation;

  /// No description provided for @nearbyLoading.
  ///
  /// In en, this message translates to:
  /// **'Finding lines around you…'**
  String get nearbyLoading;

  /// No description provided for @nearbyEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No stops nearby'**
  String get nearbyEmptyTitle;

  /// No description provided for @nearbyEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'There are no stops within walking distance of you right now.'**
  String get nearbyEmptySubtitle;

  /// No description provided for @stopUpdatedJustNow.
  ///
  /// In en, this message translates to:
  /// **'Updated just now'**
  String get stopUpdatedJustNow;

  /// No description provided for @stopUpdatedSecondsAgo.
  ///
  /// In en, this message translates to:
  /// **'Updated {seconds}s ago'**
  String stopUpdatedSecondsAgo(int seconds);

  /// No description provided for @stopUpdatedMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'Updated {minutes} min ago'**
  String stopUpdatedMinutesAgo(int minutes);

  /// No description provided for @arrivalEtaMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String arrivalEtaMinutes(int minutes);

  /// No description provided for @arrivalEtaNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get arrivalEtaNow;

  /// No description provided for @arrivalScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get arrivalScheduled;

  /// No description provided for @arrivalStopsAway.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{here} =1{1 stop away} other{{count} stops away}}'**
  String arrivalStopsAway(int count);

  /// No description provided for @vehicleMoving.
  ///
  /// In en, this message translates to:
  /// **'On the move'**
  String get vehicleMoving;

  /// No description provided for @vehicleStuck.
  ///
  /// In en, this message translates to:
  /// **'Looks stopped'**
  String get vehicleStuck;

  /// No description provided for @vehicleNextStop.
  ///
  /// In en, this message translates to:
  /// **'Next stop'**
  String get vehicleNextStop;

  /// No description provided for @vehicleUpcomingStops.
  ///
  /// In en, this message translates to:
  /// **'Rest of the route'**
  String get vehicleUpcomingStops;

  /// No description provided for @vehicleYourStop.
  ///
  /// In en, this message translates to:
  /// **'your stop'**
  String get vehicleYourStop;

  /// No description provided for @vehicleEtaApprox.
  ///
  /// In en, this message translates to:
  /// **'Arrival times are approximate'**
  String get vehicleEtaApprox;

  /// No description provided for @vehicleShowRoute.
  ///
  /// In en, this message translates to:
  /// **'Show route on map'**
  String get vehicleShowRoute;

  /// No description provided for @vehicleEtaMinutesApprox.
  ///
  /// In en, this message translates to:
  /// **'≈ {minutes} min'**
  String vehicleEtaMinutesApprox(int minutes);

  /// Title/back-chip label for the nearby view of the adaptive context slot
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get contextNearbyTitle;

  /// Header of the Fleet-ID card in the followed-vehicle view
  ///
  /// In en, this message translates to:
  /// **'About the vehicle'**
  String get aboutVehicle;

  /// CTA on the About-the-vehicle card, opens the vehicle model view
  ///
  /// In en, this message translates to:
  /// **'View model details'**
  String get viewModelDetails;

  /// Pill shown when following is interrupted (manual pan or the vehicle left the screen); recenters and resumes follow
  ///
  /// In en, this message translates to:
  /// **'Back to vehicle'**
  String get backToVehicle;

  /// Hint next to the Back-to-vehicle pill when the followed vehicle is off-screen
  ///
  /// In en, this message translates to:
  /// **'{line} is off-screen'**
  String vehicleOffScreen(String line);

  /// Shown in the followed-vehicle view for a line with no route geometry in our data (e.g. a suburban carrier)
  ///
  /// In en, this message translates to:
  /// **'Route unavailable for this line'**
  String get routeUnavailable;

  /// No description provided for @emptyArrivalsTitle.
  ///
  /// In en, this message translates to:
  /// **'It\'s quiet here right now'**
  String get emptyArrivalsTitle;

  /// No description provided for @emptyArrivalsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Something should be along shortly.'**
  String get emptyArrivalsSubtitle;

  /// No description provided for @noNetworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Looks like the connection dropped'**
  String get noNetworkTitle;

  /// No description provided for @noNetworkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and pull down to try again.'**
  String get noNetworkSubtitle;

  /// No description provided for @loadingArrivals.
  ///
  /// In en, this message translates to:
  /// **'Checking what\'s on the way…'**
  String get loadingArrivals;

  /// No description provided for @serviceKilledTitle.
  ///
  /// In en, this message translates to:
  /// **'We\'re taking a short break'**
  String get serviceKilledTitle;

  /// No description provided for @serviceKilledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Back soon.'**
  String get serviceKilledSubtitle;

  /// Thin banner above the arrivals list when the live board is down but the GTFS timetable still answers.
  ///
  /// In en, this message translates to:
  /// **'Live data temporarily unavailable — timetable'**
  String get liveUnavailableBanner;

  /// No description provided for @unknownStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Can\'t find that stop'**
  String get unknownStopTitle;

  /// No description provided for @unknownStopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'It may have been renamed or removed from the schedule.'**
  String get unknownStopSubtitle;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to My Stops'**
  String get addToFavorites;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from My Stops'**
  String get removeFromFavorites;

  /// No description provided for @pinnedRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom name'**
  String get pinnedRenameTitle;

  /// No description provided for @pinnedCustomNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Home, Work'**
  String get pinnedCustomNameHint;

  /// No description provided for @pinnedUseDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Default name'**
  String get pinnedUseDefaultName;

  /// No description provided for @pinLineTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pin line'**
  String get pinLineTooltip;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'Match system'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Map vehicle mode: vehicles shown only for a picked stop/vehicle. The map's quick toggle labels this mode.
  ///
  /// In en, this message translates to:
  /// **'On demand'**
  String get vehicleModeOnDemand;

  /// Map vehicle mode: every vehicle in the viewport (the background "aquarium")
  ///
  /// In en, this message translates to:
  /// **'All transport'**
  String get vehicleModeAll;

  /// Tooltip of the map's vehicle-mode toggle button
  ///
  /// In en, this message translates to:
  /// **'Transport on the map'**
  String get vehicleModeTooltip;

  /// Toast shown right after the map's toggle flips the mode; {mode} is vehicleModeOnDemand or vehicleModeAll
  ///
  /// In en, this message translates to:
  /// **'Transport on the map: {mode}'**
  String vehicleModeSwitched(String mode);

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About Stigla'**
  String get aboutTitle;

  /// No description provided for @aboutRouteData.
  ///
  /// In en, this message translates to:
  /// **'Route data: {date}'**
  String aboutRouteData(String date);

  /// No description provided for @aboutDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Unofficial app. Not affiliated with JKP Upravljanje javnim prevozom Beograd.'**
  String get aboutDisclaimer;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Stigla shows real-time Belgrade public transport arrivals. Built for personal use.'**
  String get aboutDescription;

  /// No description provided for @lineFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All lines'**
  String get lineFilterAll;

  /// No description provided for @alertUpcomingLabel.
  ///
  /// In en, this message translates to:
  /// **'Upcoming change'**
  String get alertUpcomingLabel;

  /// No description provided for @alertActiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Route change'**
  String get alertActiveLabel;

  /// No description provided for @alertReadMore.
  ///
  /// In en, this message translates to:
  /// **'Read more'**
  String get alertReadMore;

  /// No description provided for @alertsBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Transport changes'**
  String get alertsBannerTitle;

  /// No description provided for @vehicleTypeBus.
  ///
  /// In en, this message translates to:
  /// **'Bus'**
  String get vehicleTypeBus;

  /// No description provided for @vehicleTypeTram.
  ///
  /// In en, this message translates to:
  /// **'Tram'**
  String get vehicleTypeTram;

  /// No description provided for @vehicleTypeTrolleybus.
  ///
  /// In en, this message translates to:
  /// **'Trolleybus'**
  String get vehicleTypeTrolleybus;

  /// No description provided for @fleetAgeYears.
  ///
  /// In en, this message translates to:
  /// **'{years} yr'**
  String fleetAgeYears(int years);

  /// No description provided for @fleetVehicleNumber.
  ///
  /// In en, this message translates to:
  /// **'#{number}'**
  String fleetVehicleNumber(String number);

  /// No description provided for @fleetSortByTime.
  ///
  /// In en, this message translates to:
  /// **'By time'**
  String get fleetSortByTime;

  /// No description provided for @fleetSortByComfort.
  ///
  /// In en, this message translates to:
  /// **'By comfort'**
  String get fleetSortByComfort;

  /// No description provided for @fleetUnknownModel.
  ///
  /// In en, this message translates to:
  /// **'Model unknown'**
  String get fleetUnknownModel;

  /// No description provided for @fleetSectionComfort.
  ///
  /// In en, this message translates to:
  /// **'Comfort'**
  String get fleetSectionComfort;

  /// No description provided for @fleetSectionAmenities.
  ///
  /// In en, this message translates to:
  /// **'On board'**
  String get fleetSectionAmenities;

  /// No description provided for @fleetSectionDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get fleetSectionDetails;

  /// No description provided for @fleetAc.
  ///
  /// In en, this message translates to:
  /// **'Air conditioning'**
  String get fleetAc;

  /// No description provided for @fleetNoAc.
  ///
  /// In en, this message translates to:
  /// **'No air conditioning'**
  String get fleetNoAc;

  /// No description provided for @fleetLowFloor.
  ///
  /// In en, this message translates to:
  /// **'Low floor'**
  String get fleetLowFloor;

  /// No description provided for @fleetHighFloor.
  ///
  /// In en, this message translates to:
  /// **'Steps at the door'**
  String get fleetHighFloor;

  /// No description provided for @fleetArticulated.
  ///
  /// In en, this message translates to:
  /// **'Articulated (bendy)'**
  String get fleetArticulated;

  /// No description provided for @fleetUsb.
  ///
  /// In en, this message translates to:
  /// **'USB charging'**
  String get fleetUsb;

  /// No description provided for @fleetElectric.
  ///
  /// In en, this message translates to:
  /// **'Electric'**
  String get fleetElectric;

  /// No description provided for @fleetHybrid.
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get fleetHybrid;

  /// No description provided for @fleetCng.
  ///
  /// In en, this message translates to:
  /// **'Runs on gas (CNG)'**
  String get fleetCng;

  /// No description provided for @fleetTrolley.
  ///
  /// In en, this message translates to:
  /// **'Trolleybus'**
  String get fleetTrolley;

  /// No description provided for @fleetTram.
  ///
  /// In en, this message translates to:
  /// **'Tram'**
  String get fleetTram;

  /// No description provided for @fleetDiesel.
  ///
  /// In en, this message translates to:
  /// **'Diesel'**
  String get fleetDiesel;

  /// No description provided for @fleetAge.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get fleetAge;

  /// No description provided for @fleetAgeApprox.
  ///
  /// In en, this message translates to:
  /// **'~{years} yr (built {from}–{to})'**
  String fleetAgeApprox(int years, int from, int to);

  /// No description provided for @fleetCapacity.
  ///
  /// In en, this message translates to:
  /// **'Holds ~{count}'**
  String fleetCapacity(int count);

  /// No description provided for @fleetLength.
  ///
  /// In en, this message translates to:
  /// **'{meters} m long'**
  String fleetLength(String meters);

  /// No description provided for @fleetOperator.
  ///
  /// In en, this message translates to:
  /// **'Operator: {name}'**
  String fleetOperator(String name);

  /// No description provided for @fleetManufacturer.
  ///
  /// In en, this message translates to:
  /// **'Manufacturer: {value}'**
  String fleetManufacturer(String value);

  /// No description provided for @fleetComfortRetro.
  ///
  /// In en, this message translates to:
  /// **'retro'**
  String get fleetComfortRetro;

  /// No description provided for @fleetComfortOk.
  ///
  /// In en, this message translates to:
  /// **'ok'**
  String get fleetComfortOk;

  /// No description provided for @fleetComfortComfy.
  ///
  /// In en, this message translates to:
  /// **'comfort'**
  String get fleetComfortComfy;

  /// No description provided for @fleetApproxNote.
  ///
  /// In en, this message translates to:
  /// **'“~” marks values estimated for this operator, not confirmed for this exact vehicle.'**
  String get fleetApproxNote;

  /// No description provided for @navCoverage.
  ///
  /// In en, this message translates to:
  /// **'Coverage'**
  String get navCoverage;

  /// No description provided for @coverageFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get coverageFilterAll;

  /// No description provided for @coverageLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'Transit density'**
  String get coverageLegendTitle;

  /// No description provided for @coverageLegendLow.
  ///
  /// In en, this message translates to:
  /// **'rarer'**
  String get coverageLegendLow;

  /// No description provided for @coverageLegendHigh.
  ///
  /// In en, this message translates to:
  /// **'busier'**
  String get coverageLegendHigh;

  /// No description provided for @coverageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Coverage map is unavailable right now.'**
  String get coverageUnavailable;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru', 'sr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'sr':
      return AppLocalizationsSr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
