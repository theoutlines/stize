// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Serbian (`sr`).
class AppLocalizationsSr extends AppLocalizations {
  AppLocalizationsSr([String locale = 'sr']) : super(locale);

  @override
  String get appTitle => 'Stigla';

  @override
  String get navMyStops => 'Moja stajališta';

  @override
  String get navSearch => 'Pretraga';

  @override
  String get navAbout => 'O aplikaciji';

  @override
  String get myStopsEmptyTitle => 'Još nemaš omiljena stajališta';

  @override
  String get myStopsEmptySubtitle =>
      'Pronađi stajalište, ulicu ili liniju i dodaj je ovde.';

  @override
  String get searchHint => 'Stajalište, ulica ili linija…';

  @override
  String get searchNoResults => 'Ništa nije pronađeno. Probaj drugačiji unos.';

  @override
  String get stopUpdatedJustNow => 'Ažurirano upravo sada';

  @override
  String stopUpdatedSecondsAgo(int seconds) {
    return 'Ažurirano pre $seconds sek';
  }

  @override
  String stopUpdatedMinutesAgo(int minutes) {
    return 'Ažurirano pre $minutes min';
  }

  @override
  String arrivalEtaMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get arrivalEtaNow => 'Sada';

  @override
  String arrivalStopsAway(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stanica',
      few: '$count stanice',
      one: '$count stanica',
      zero: 'ovde',
    );
    return '$_temp0';
  }

  @override
  String get emptyArrivalsTitle => 'Trenutno je tiho na ovom stajalištu';

  @override
  String get emptyArrivalsSubtitle => 'Prevoz bi trebalo uskoro da stigne.';

  @override
  String get noNetworkTitle => 'Izgleda da je internet nestao';

  @override
  String get noNetworkSubtitle =>
      'Proveri vezu i povuci na dole da pokušaš ponovo.';

  @override
  String get loadingArrivals => 'Gledamo šta dolazi…';

  @override
  String get serviceKilledTitle => 'Pravimo kratku pauzu';

  @override
  String get serviceKilledSubtitle => 'Vraćamo se uskoro.';

  @override
  String get unknownStopTitle => 'Ne mogu da pronađem to stajalište';

  @override
  String get unknownStopSubtitle =>
      'Možda je preimenovano ili uklonjeno iz reda vožnje.';

  @override
  String get retry => 'Pokušaj ponovo';

  @override
  String get addToFavorites => 'Dodaj u Moja stajališta';

  @override
  String get removeFromFavorites => 'Ukloni iz Mojih stajališta';

  @override
  String get settingsTitle => 'Podešavanja';

  @override
  String get settingsLanguage => 'Jezik';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeSystem => 'Prati sistem';

  @override
  String get settingsThemeLight => 'Svetla';

  @override
  String get settingsThemeDark => 'Tamna';

  @override
  String get settingsRefreshInterval => 'Interval osvežavanja';

  @override
  String settingsRefreshIntervalSeconds(int seconds) {
    return '$seconds sek';
  }

  @override
  String get aboutTitle => 'O Stigla aplikaciji';

  @override
  String get aboutDisclaimer =>
      'Nezvanična aplikacija. Nije povezana sa JKP Upravljanje javnim prevozom Beograd.';

  @override
  String get aboutDescription =>
      'Stigla prikazuje dolaske javnog prevoza u Beogradu u realnom vremenu. Napravljeno za ličnu upotrebu.';

  @override
  String get lineFilterAll => 'Sve linije';

  @override
  String get vehicleTypeBus => 'Autobus';

  @override
  String get vehicleTypeTram => 'Tramvaj';

  @override
  String get vehicleTypeTrolleybus => 'Trolejbus';
}
