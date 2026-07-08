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

  /// No description provided for @navMyStops.
  ///
  /// In en, this message translates to:
  /// **'My Stops'**
  String get navMyStops;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

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

  /// No description provided for @arrivalStopsAway.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{here} =1{1 stop away} other{{count} stops away}}'**
  String arrivalStopsAway(int count);

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

  /// No description provided for @settingsRefreshInterval.
  ///
  /// In en, this message translates to:
  /// **'Refresh interval'**
  String get settingsRefreshInterval;

  /// No description provided for @settingsRefreshIntervalSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String settingsRefreshIntervalSeconds(int seconds);

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About Stigla'**
  String get aboutTitle;

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
