import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
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
    Locale('sr'),
  ];

  /// App name, shown in title bars and the OS app switcher
  ///
  /// In en, this message translates to:
  /// **'Stiže'**
  String get appTitle;


  /// No description provided for @navMyStops.
  ///
  /// In en, this message translates to:
  /// **'My Stops'**
  String get navMyStops;

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

  /// Section label between nearby matches and global stop/line results in the unified mobile search
  ///
  /// In en, this message translates to:
  /// **'More results'**
  String get searchMoreResults;

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


  /// No description provided for @vehicleScheduled.
  ///
  /// In en, this message translates to:
  /// **'By schedule — not a live position'**
  String get vehicleScheduled;

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

  /// The 'min' unit under the big ETA number on an arrival card
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get arrivalEtaMinutesUnit;

  /// No description provided for @arrivalEtaNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get arrivalEtaNow;

  /// No description provided for @arrivalStopsAway.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{At the stop} =1{1 stop away} other{{count} stops away}}'**
  String arrivalStopsAway(int count);









  /// Title/back-chip label for the nearby view of the adaptive context slot
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get contextNearbyTitle;

  /// Pill shown when following is interrupted (manual pan or the vehicle left the screen); recenters and resumes follow
  ///
  /// In en, this message translates to:
  /// **'Back to vehicle'**
  String get backToVehicle;

  /// Start of the "Back to <line badge>" pill when the followed vehicle left the view.
  ///
  /// In en, this message translates to:
  /// **'Back to'**
  String get backTo;


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

  /// No description provided for @vehicleModeHint.
  ///
  /// In en, this message translates to:
  /// **'Live transport'**
  String get vehicleModeHint;

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
  /// **'About Stiže'**
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


  /// No description provided for @fleetVehicleNumber.
  ///
  /// In en, this message translates to:
  /// **'#{number}'**
  String fleetVehicleNumber(String number);

  /// No description provided for @fleetUnknownModel.
  ///
  /// In en, this message translates to:
  /// **'Model unknown'**
  String get fleetUnknownModel;


  /// No description provided for @fleetAc.
  ///
  /// In en, this message translates to:
  /// **'Air conditioning'**
  String get fleetAc;







  /// No description provided for @fleetHybrid.
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get fleetHybrid;











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

  /// Drawer footer list item that opens the feedback actions sheet
  ///
  /// In en, this message translates to:
  /// **'Share feedback'**
  String get drawerShareFeedback;

  /// No description provided for @drawerFeedbackSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get drawerFeedbackSheetTitle;





  /// No description provided for @feedbackFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Write to me'**
  String get feedbackFormTitle;

  /// No description provided for @feedbackMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Your message'**
  String get feedbackMessageLabel;

  /// No description provided for @feedbackMessageHint.
  ///
  /// In en, this message translates to:
  /// **'A bug, an idea, a kind word…'**
  String get feedbackMessageHint;

  /// No description provided for @feedbackContactLabel.
  ///
  /// In en, this message translates to:
  /// **'Contact (optional)'**
  String get feedbackContactLabel;

  /// No description provided for @feedbackContactHint.
  ///
  /// In en, this message translates to:
  /// **'Email or Telegram, if you want a reply'**
  String get feedbackContactHint;

  /// No description provided for @feedbackSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get feedbackSend;

  /// No description provided for @feedbackSent.
  ///
  /// In en, this message translates to:
  /// **'Thanks — your message was sent.'**
  String get feedbackSent;

  /// No description provided for @feedbackErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send. Please try again later.'**
  String get feedbackErrorGeneric;

  /// No description provided for @feedbackErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Please wait a moment before sending more.'**
  String get feedbackErrorRateLimited;

  /// No description provided for @feedbackEmptyValidation.
  ///
  /// In en, this message translates to:
  /// **'Write a message first.'**
  String get feedbackEmptyValidation;

  /// No description provided for @drawerLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get drawerLicenses;

  /// No description provided for @drawerPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get drawerPrivacy;

  /// No description provided for @licensesLegalese.
  ///
  /// In en, this message translates to:
  /// **'Stiže is free software under the AGPL-3.0 license.'**
  String get licensesLegalese;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyTitle;

  /// No description provided for @privacyIntro.
  ///
  /// In en, this message translates to:
  /// **'Stiže is private by default. Here\'s exactly what it does with data, in plain language.'**
  String get privacyIntro;

  /// No description provided for @privacyLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Your location'**
  String get privacyLocationTitle;

  /// No description provided for @privacyLocationBody.
  ///
  /// In en, this message translates to:
  /// **'When you ask to see nearby stops and vehicles, your device\'s location is sent to our API with that request to find what\'s around you. It is used only to answer that request and is never stored on our servers.'**
  String get privacyLocationBody;

  /// No description provided for @privacyAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Anonymous usage'**
  String get privacyAnalyticsTitle;

  /// No description provided for @privacyAnalyticsBody.
  ///
  /// In en, this message translates to:
  /// **'The app may record anonymous usage events (for example, that a stop was opened) to understand which features are used. These carry no identifiers and no accounts, and cannot be traced back to you.'**
  String get privacyAnalyticsBody;

  /// No description provided for @privacyTrackersTitle.
  ///
  /// In en, this message translates to:
  /// **'No ads, no trackers'**
  String get privacyTrackersTitle;

  /// No description provided for @privacyTrackersBody.
  ///
  /// In en, this message translates to:
  /// **'Stiže shows no ads and includes no third-party advertising or tracking SDKs.'**
  String get privacyTrackersBody;

  /// No description provided for @privacyFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Feedback you send'**
  String get privacyFeedbackTitle;

  /// No description provided for @privacyFeedbackBody.
  ///
  /// In en, this message translates to:
  /// **'If you send feedback, your message — and the optional contact you provide — are stored so we can read it and reply to you. Nothing else is collected with it.'**
  String get privacyFeedbackBody;

  /// No description provided for @privacyServicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Services the app loads from'**
  String get privacyServicesTitle;

  /// No description provided for @privacyServicesBody.
  ///
  /// In en, this message translates to:
  /// **'Like any website, the app loads some parts from other services, which see your IP address as part of the request: map tiles for the area you view come from MapTiler, fonts and parts of the app engine from Google (gstatic.com), and the app and its API are served by Cloudflare. None of them receive your location from us or any account details.'**
  String get privacyServicesBody;

  /// No description provided for @privacyOpenSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get privacyOpenSourceTitle;

  /// No description provided for @privacyOpenSourceBody.
  ///
  /// In en, this message translates to:
  /// **'Stiže\'s code is open source under the AGPL-3.0 license, so anyone can inspect exactly how it works.'**
  String get privacyOpenSourceBody;

  /// No description provided for @jamStopBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Trams {line} have been stopped longer than usual — possible delay'**
  String jamStopBannerTitle(String line);

  /// No description provided for @jamSubstitutionNotice.
  ///
  /// In en, this message translates to:
  /// **'Buses are running instead of trams on line {line}'**
  String jamSubstitutionNotice(String line);

  /// No description provided for @jamModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show stalled segments'**
  String get jamModeTooltip;

  /// No description provided for @jamNearbyDelay.
  ///
  /// In en, this message translates to:
  /// **'Possible delay on line {line}'**
  String jamNearbyDelay(String line);

  /// No description provided for @jamAffectedStopsTitle.
  ///
  /// In en, this message translates to:
  /// **'Affected stops'**
  String get jamAffectedStopsTitle;

  /// No description provided for @jamFollowAhead.
  ///
  /// In en, this message translates to:
  /// **'Possible delay ahead on the route'**
  String get jamFollowAhead;

  /// Destination label when the line ends at the stop being viewed.
  ///
  /// In en, this message translates to:
  /// **'Terminus'**
  String get arrivalTerminus;

  /// No description provided for @stopMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get stopMore;

  /// No description provided for @stopReportProblem.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get stopReportProblem;

  /// No description provided for @stopInMyStops.
  ///
  /// In en, this message translates to:
  /// **'In My Stops'**
  String get stopInMyStops;

  /// No description provided for @stopReportTitle.
  ///
  /// In en, this message translates to:
  /// **'What’s wrong?'**
  String get stopReportTitle;

  /// No description provided for @stopReportNotHere.
  ///
  /// In en, this message translates to:
  /// **'The stop isn’t here or it’s elsewhere'**
  String get stopReportNotHere;

  /// No description provided for @stopReportWrongType.
  ///
  /// In en, this message translates to:
  /// **'Wrong type (bus, tram, trolleybus)'**
  String get stopReportWrongType;

  /// No description provided for @stopReportWrongLines.
  ///
  /// In en, this message translates to:
  /// **'Wrong lines'**
  String get stopReportWrongLines;

  /// No description provided for @stopReportArrivalsWrong.
  ///
  /// In en, this message translates to:
  /// **'Arrivals don’t match reality'**
  String get stopReportArrivalsWrong;

  /// No description provided for @stopReportWrongName.
  ///
  /// In en, this message translates to:
  /// **'Wrong name'**
  String get stopReportWrongName;

  /// No description provided for @stopReportOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get stopReportOther;

  /// No description provided for @stopReportOtherLabel.
  ///
  /// In en, this message translates to:
  /// **'Tell us what’s wrong'**
  String get stopReportOtherLabel;

  /// No description provided for @stopReportOtherHint.
  ///
  /// In en, this message translates to:
  /// **'Needed for “Something else”'**
  String get stopReportOtherHint;

  /// No description provided for @stopReportPrivacy.
  ///
  /// In en, this message translates to:
  /// **'We get the stop and its lines. Not your location.'**
  String get stopReportPrivacy;

  /// No description provided for @stopReportSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get stopReportSend;

  /// No description provided for @stopReportSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Thanks, got it'**
  String get stopReportSentTitle;

  /// No description provided for @stopReportSentBody.
  ///
  /// In en, this message translates to:
  /// **'We’ll check “{what}” at {stop} and fix the data. You don’t need to do anything else.'**
  String stopReportSentBody(String what, String stop);

  /// No description provided for @stopReportAlreadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Already sent today'**
  String get stopReportAlreadyTitle;

  /// No description provided for @stopReportAlreadyBody.
  ///
  /// In en, this message translates to:
  /// **'You told us about “{what}” at this stop today. One report is enough: we’ll check it.'**
  String stopReportAlreadyBody(String what);

  /// No description provided for @stopReportBack.
  ///
  /// In en, this message translates to:
  /// **'Back to the stop'**
  String get stopReportBack;

  /// No description provided for @stopReportTooFast.
  ///
  /// In en, this message translates to:
  /// **'Please wait a minute before sending another report.'**
  String get stopReportTooFast;

  /// No description provided for @stopReportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t send. Check the connection and try again.'**
  String get stopReportFailed;

  /// Open-data attribution required by the licence (source body, where published, that the data is modified).
  ///
  /// In en, this message translates to:
  /// **'Stops, lines and timetables: open data of the City of Belgrade (Secretariat for Public Transport), published on data.gov.rs under the Serbian open data licence. We repackage them for the app. Map: MapTiler, OpenStreetMap contributors.'**
  String get aboutDataSource;

  /// No description provided for @menuSupport.
  ///
  /// In en, this message translates to:
  /// **'Support Stiže'**
  String get menuSupport;

  /// No description provided for @menuClose.
  ///
  /// In en, this message translates to:
  /// **'Close menu'**
  String get menuClose;

  /// No description provided for @settingsAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsAuto;

  /// No description provided for @settingsAutoHint.
  ///
  /// In en, this message translates to:
  /// **'Auto follows your phone. Transport on the map is switched with the layers button on the map.'**
  String get settingsAutoHint;

  /// No description provided for @guideTitle.
  ///
  /// In en, this message translates to:
  /// **'Belgrade guide'**
  String get guideTitle;

  /// No description provided for @guideFree.
  ///
  /// In en, this message translates to:
  /// **'City transport is free: buses, trams, trolleybuses'**
  String get guideFree;

  /// No description provided for @guideGettingAround.
  ///
  /// In en, this message translates to:
  /// **'Getting around'**
  String get guideGettingAround;

  /// No description provided for @guideFromAirport.
  ///
  /// In en, this message translates to:
  /// **'From the airport'**
  String get guideFromAirport;

  /// No description provided for @guideFromAirportSub.
  ///
  /// In en, this message translates to:
  /// **'Lines 72, A1, 600, 607 · 72N at night'**
  String get guideFromAirportSub;

  /// No description provided for @guideFromBusStation.
  ///
  /// In en, this message translates to:
  /// **'From the bus station'**
  String get guideFromBusStation;

  /// No description provided for @guideFromBusStationSub.
  ///
  /// In en, this message translates to:
  /// **'Beogradska autobuska stanica, New Belgrade'**
  String get guideFromBusStationSub;

  /// No description provided for @guideFromRailStation.
  ///
  /// In en, this message translates to:
  /// **'From the railway station'**
  String get guideFromRailStation;

  /// No description provided for @guideFromRailStationSub.
  ///
  /// In en, this message translates to:
  /// **'Beograd Centar (Prokop)'**
  String get guideFromRailStationSub;

  /// No description provided for @guideReadStop.
  ///
  /// In en, this message translates to:
  /// **'How to read a stop'**
  String get guideReadStop;

  /// No description provided for @guideReadStopSub.
  ///
  /// In en, this message translates to:
  /// **'Live minutes and timetable times'**
  String get guideReadStopSub;

  /// No description provided for @guideReadStopLive.
  ///
  /// In en, this message translates to:
  /// **'Big minutes are live: the vehicle is on its way and we see it on GPS.'**
  String get guideReadStopLive;

  /// No description provided for @guideReadStopScheduled.
  ///
  /// In en, this message translates to:
  /// **'A time of day is from the timetable: no live signal for that trip yet.'**
  String get guideReadStopScheduled;

  /// No description provided for @guideReadStopStar.
  ///
  /// In en, this message translates to:
  /// **'Tap the star to keep a stop in My stops.'**
  String get guideReadStopStar;

  /// No description provided for @guideReadStopNight.
  ///
  /// In en, this message translates to:
  /// **'Lines ending in N run at night.'**
  String get guideReadStopNight;

  /// No description provided for @guidePlaces.
  ///
  /// In en, this message translates to:
  /// **'Places people ask for'**
  String get guidePlaces;

  /// No description provided for @guidePlacesSub.
  ///
  /// In en, this message translates to:
  /// **'Fortress, squares, stations, Ada'**
  String get guidePlacesSub;

  /// No description provided for @guideNowLabel.
  ///
  /// In en, this message translates to:
  /// **'Right now'**
  String get guideNowLabel;

  /// No description provided for @guideExpoTitle.
  ///
  /// In en, this message translates to:
  /// **'Expo 2027 in Belgrade'**
  String get guideExpoTitle;

  /// No description provided for @guideExpoDays.
  ///
  /// In en, this message translates to:
  /// **'days to opening'**
  String get guideExpoDays;

  /// No description provided for @guideExpoSub.
  ///
  /// In en, this message translates to:
  /// **'15 May to 15 August 2027. We add the Expo lines as soon as the city announces them.'**
  String get guideExpoSub;

  /// No description provided for @guideNightTitle.
  ///
  /// In en, this message translates to:
  /// **'Night lines are running'**
  String get guideNightTitle;

  /// No description provided for @guideNightSub.
  ///
  /// In en, this message translates to:
  /// **'After midnight the night lines take over. Their numbers end in N.'**
  String get guideNightSub;

  /// No description provided for @guideStripNight.
  ///
  /// In en, this message translates to:
  /// **'Night lines are running'**
  String get guideStripNight;

  /// No description provided for @guideStripNightSub.
  ///
  /// In en, this message translates to:
  /// **'What runs after midnight'**
  String get guideStripNightSub;

  /// No description provided for @guideStripNew.
  ///
  /// In en, this message translates to:
  /// **'New to Belgrade? Open the guide'**
  String get guideStripNew;

  /// No description provided for @guideStripNewSub.
  ///
  /// In en, this message translates to:
  /// **'Free rides, airport, night lines'**
  String get guideStripNewSub;

  /// No description provided for @guideStripAirport.
  ///
  /// In en, this message translates to:
  /// **'You\'re at the airport'**
  String get guideStripAirport;

  /// No description provided for @guideStripAirportSub.
  ///
  /// In en, this message translates to:
  /// **'Into the city: 72, A1, 600'**
  String get guideStripAirportSub;

  /// No description provided for @guideStripBusStation.
  ///
  /// In en, this message translates to:
  /// **'You\'re at the bus station'**
  String get guideStripBusStation;

  /// No description provided for @guideStripBusStationSub.
  ///
  /// In en, this message translates to:
  /// **'City lines leave from the stops by the exit'**
  String get guideStripBusStationSub;

  /// No description provided for @guideStripRailStation.
  ///
  /// In en, this message translates to:
  /// **'You\'re at Beograd Centar station'**
  String get guideStripRailStation;

  /// No description provided for @guideStripRailStationSub.
  ///
  /// In en, this message translates to:
  /// **'City lines: 34, 36, 600'**
  String get guideStripRailStationSub;

  /// Card subtitle for a vehicle that ends its trip at this stop and then starts back: where it goes next.
  ///
  /// In en, this message translates to:
  /// **'Then to {place}'**
  String arrivalThenTo(String place);

  /// No description provided for @locateMeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show where I am'**
  String get locateMeTooltip;

  /// No description provided for @nearbyAroundYou.
  ///
  /// In en, this message translates to:
  /// **'Around you'**
  String get nearbyAroundYou;

  /// No description provided for @cityTitle.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get cityTitle;

  /// No description provided for @cityHeadline.
  ///
  /// In en, this message translates to:
  /// **'How Belgrade transport runs'**
  String get cityHeadline;

  /// No description provided for @citySubtitle.
  ///
  /// In en, this message translates to:
  /// **'From arrivals our users saw'**
  String get citySubtitle;

  /// No description provided for @cityKpiDelay.
  ///
  /// In en, this message translates to:
  /// **'Average delay'**
  String get cityKpiDelay;

  /// No description provided for @cityKpiInterval.
  ///
  /// In en, this message translates to:
  /// **'Typical interval'**
  String get cityKpiInterval;

  /// No description provided for @cityKpiLines.
  ///
  /// In en, this message translates to:
  /// **'Lines seen'**
  String get cityKpiLines;

  /// No description provided for @cityKpiArrivals.
  ///
  /// In en, this message translates to:
  /// **'Arrivals seen'**
  String get cityKpiArrivals;

  /// No description provided for @cityMin.
  ///
  /// In en, this message translates to:
  /// **'{n} min'**
  String cityMin(int n);

  /// No description provided for @cityOnTime.
  ///
  /// In en, this message translates to:
  /// **'on time'**
  String get cityOnTime;

  /// No description provided for @cityLateBy.
  ///
  /// In en, this message translates to:
  /// **'{n} min late'**
  String cityLateBy(int n);

  /// No description provided for @cityEarlyBy.
  ///
  /// In en, this message translates to:
  /// **'{n} min early'**
  String cityEarlyBy(int n);

  /// No description provided for @cityHeatTitle.
  ///
  /// In en, this message translates to:
  /// **'When it runs late'**
  String get cityHeatTitle;

  /// No description provided for @cityHeatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Average delay by weekday and hour'**
  String get cityHeatSubtitle;

  /// No description provided for @cityLegendLow.
  ///
  /// In en, this message translates to:
  /// **'on time'**
  String get cityLegendLow;

  /// No description provided for @cityLegendHigh.
  ///
  /// In en, this message translates to:
  /// **'often late'**
  String get cityLegendHigh;

  /// No description provided for @cityHeatWorst.
  ///
  /// In en, this message translates to:
  /// **'Worst: {day} at {hour}:00, about {min} min late.'**
  String cityHeatWorst(String day, int hour, int min);

  /// No description provided for @cityHeatCell.
  ///
  /// In en, this message translates to:
  /// **'{day} {hour}:00–{next}:00'**
  String cityHeatCell(String day, int hour, int next);

  /// No description provided for @cityHeatCellCount.
  ///
  /// In en, this message translates to:
  /// **'{n} arrivals'**
  String cityHeatCellCount(int n);

  /// No description provided for @cityHeatFew.
  ///
  /// In en, this message translates to:
  /// **'too few arrivals'**
  String get cityHeatFew;

  /// No description provided for @cityLinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get cityLinesTitle;

  /// No description provided for @cityLinesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Size: arrivals seen · number: average delay'**
  String get cityLinesSubtitle;

  /// No description provided for @cityLinesSummary.
  ///
  /// In en, this message translates to:
  /// **'{best} is the most punctual line. {worst} runs the latest.'**
  String cityLinesSummary(String best, String worst);

  /// No description provided for @cityLegendBest.
  ///
  /// In en, this message translates to:
  /// **'best'**
  String get cityLegendBest;

  /// No description provided for @cityLegendWorst.
  ///
  /// In en, this message translates to:
  /// **'worst'**
  String get cityLegendWorst;

  /// No description provided for @cityLegendThin.
  ///
  /// In en, this message translates to:
  /// **'too few arrivals to judge'**
  String get cityLegendThin;

  /// No description provided for @cityIntervalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Longest real intervals'**
  String get cityIntervalsTitle;

  /// No description provided for @cityIntervalsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Evenings 21:00 to 01:00, average wait'**
  String get cityIntervalsSubtitle;

  /// No description provided for @cityNote.
  ///
  /// In en, this message translates to:
  /// **'We only see stops people open, at the hours they open them. Lines with too few arrivals are not ranked.'**
  String get cityNote;

  /// No description provided for @cityEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Not enough arrivals yet'**
  String get cityEmptyTitle;

  /// No description provided for @cityEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Stats appear once we have seen at least {min} arrivals.'**
  String cityEmptyBody(int min);

  /// No description provided for @cityLineUsual.
  ///
  /// In en, this message translates to:
  /// **'Usually at this hour'**
  String get cityLineUsual;

  /// No description provided for @cityLineEvery.
  ///
  /// In en, this message translates to:
  /// **'every {n} min'**
  String cityLineEvery(int n);

  /// No description provided for @cityLineHeatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This line, by weekday and hour'**
  String get cityLineHeatSubtitle;

  /// No description provided for @cityLineThinBody.
  ///
  /// In en, this message translates to:
  /// **'We have seen {n} arrivals of this line. Stats appear after {min}.'**
  String cityLineThinBody(int n, int min);

  /// No description provided for @cityLineNoHour.
  ///
  /// In en, this message translates to:
  /// **'no data for this hour'**
  String get cityLineNoHour;

  /// No description provided for @cityLinesBestOnly.
  ///
  /// In en, this message translates to:
  /// **'{best} is the most punctual line; none of the busy lines runs notably late.'**
  String cityLinesBestOnly(String best);

  /// No description provided for @arrivalNextList.
  ///
  /// In en, this message translates to:
  /// **'next {times} min'**
  String arrivalNextList(String times);

  /// No description provided for @arrivalStartsHere.
  ///
  /// In en, this message translates to:
  /// **'Starts here'**
  String get arrivalStartsHere;

  /// No description provided for @arrivalByTimetable.
  ///
  /// In en, this message translates to:
  /// **'By timetable'**
  String get arrivalByTimetable;

  /// No description provided for @followStopsTo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stop to {stop}} other{{count} stops to {stop}}}'**
  String followStopsTo(int count, String stop);

  /// No description provided for @followAtStop.
  ///
  /// In en, this message translates to:
  /// **'At {stop}'**
  String followAtStop(String stop);

  /// No description provided for @followNextStop.
  ///
  /// In en, this message translates to:
  /// **'Next: {stop}'**
  String followNextStop(String stop);

  /// No description provided for @followStuck.
  ///
  /// In en, this message translates to:
  /// **'Stuck · {minutes} min'**
  String followStuck(int minutes);

  /// No description provided for @followYourStop.
  ///
  /// In en, this message translates to:
  /// **'Your stop'**
  String get followYourStop;

  /// No description provided for @fleetChipAge.
  ///
  /// In en, this message translates to:
  /// **'{years} yr'**
  String fleetChipAge(int years);

  /// No description provided for @fleetChipCapacity.
  ///
  /// In en, this message translates to:
  /// **'~{count} people'**
  String fleetChipCapacity(int count);

  /// No description provided for @fleetChipComfort.
  ///
  /// In en, this message translates to:
  /// **'Comfort: {word}'**
  String fleetChipComfort(String word);

  /// No description provided for @fleetChipSteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get fleetChipSteps;

  /// No description provided for @fleetChipLowFloor.
  ///
  /// In en, this message translates to:
  /// **'Low floor'**
  String get fleetChipLowFloor;

  /// No description provided for @fleetMadeBy.
  ///
  /// In en, this message translates to:
  /// **'Made by {value}'**
  String fleetMadeBy(String value);

  /// No description provided for @fleetOperatorShort.
  ///
  /// In en, this message translates to:
  /// **'Operator {name}'**
  String fleetOperatorShort(String name);

  /// No description provided for @fleetPhotoShort.
  ///
  /// In en, this message translates to:
  /// **'Photo: {author}, {license}'**
  String fleetPhotoShort(String author, String license);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @fleetChipArticulated.
  ///
  /// In en, this message translates to:
  /// **'Articulated'**
  String get fleetChipArticulated;

  /// No description provided for @fleetChipAc.
  ///
  /// In en, this message translates to:
  /// **'A/C'**
  String get fleetChipAc;

  /// No description provided for @fleetChipNoAc.
  ///
  /// In en, this message translates to:
  /// **'No A/C'**
  String get fleetChipNoAc;

  /// No description provided for @nearbyThisPoint.
  ///
  /// In en, this message translates to:
  /// **'Around this point'**
  String get nearbyThisPoint;
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
      <String>['en', 'sr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
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
