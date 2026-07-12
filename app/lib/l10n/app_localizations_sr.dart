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
  String get navHome => 'Mapa';

  @override
  String get navMyStops => 'Moja stajališta';

  @override
  String get navIdeas => 'Ideje';

  @override
  String get navAbout => 'O aplikaciji';

  @override
  String get ideasEmptyTitle => 'Još nema ideja';

  @override
  String get ideasEmptySubtitle => 'Budi prvi koji će nešto predložiti.';

  @override
  String get ideaInputHint => 'Šta bi Stigla trebalo da radi bolje?';

  @override
  String get ideaSubmit => 'Predloži';

  @override
  String get ideaRateLimited =>
      'Jedna ideja odjednom — probaj ponovo za nekoliko minuta.';

  @override
  String ideaVotesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count glasova',
      few: '$count glasa',
      one: '$count glas',
      zero: 'Još nema glasova',
    );
    return '$_temp0';
  }

  @override
  String get ideaCommentsTitle => 'Komentari';

  @override
  String get ideaCommentInputHint => 'Dodaj komentar…';

  @override
  String get ideaCommentSubmit => 'Pošalji';

  @override
  String get ideaCommentsEmpty => 'Još nema komentara.';

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
  String get locationDenied =>
      'Pristup lokaciji je odbijen. Dozvoli ga u pregledaču ili podešavanjima da vidiš gde se nalaziš.';

  @override
  String get locationServicesOff =>
      'Usluge lokacije su isključene. Uključi ih u podešavanjima uređaja.';

  @override
  String get locationTimeout =>
      'Nije uspelo određivanje lokacije na vreme. Proveri vezu i pokušaj ponovo.';

  @override
  String get locationUnavailable =>
      'Lokacija trenutno nije dostupna. Pokušaj za trenutak.';

  @override
  String get nearbyStopsTitle => 'Stajališta u blizini';

  @override
  String get nearbyStopsEmpty =>
      'Uključi lokaciju ili pretraži stajalište, ulicu ili liniju iznad.';

  @override
  String get mapZoomInForVehicles => 'Uvećaj mapu da vidiš prevoz uživo';

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
  String get vehicleMoving => 'U pokretu';

  @override
  String get vehicleStuck => 'Izgleda da stoji';

  @override
  String get vehicleNextStop => 'Sledeća stanica';

  @override
  String get vehicleUpcomingStops => 'Dalje na ruti';

  @override
  String get vehicleYourStop => 'vaša stanica';

  @override
  String get vehicleEtaApprox => 'Vremena dolaska su okvirna';

  @override
  String get vehicleShowRoute => 'Prikaži rutu na mapi';

  @override
  String vehicleEtaMinutesApprox(int minutes) {
    return '≈ $minutes min';
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
  String get pinnedRenameTitle => 'Naziv po meri';

  @override
  String get pinnedCustomNameHint => 'npr. Kuća, Posao';

  @override
  String get pinnedUseDefaultName => 'Podrazumevano ime';

  @override
  String get pinLineTooltip => 'Zakači liniju';

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
  String get alertUpcomingLabel => 'Uskoro promena';

  @override
  String get alertActiveLabel => 'Promena linije';

  @override
  String get alertReadMore => 'Više detalja';

  @override
  String get alertsBannerTitle => 'Izmene u prevozu';

  @override
  String get vehicleTypeBus => 'Autobus';

  @override
  String get vehicleTypeTram => 'Tramvaj';

  @override
  String get vehicleTypeTrolleybus => 'Trolejbus';

  @override
  String fleetAgeYears(int years) {
    return '$years god.';
  }

  @override
  String fleetVehicleNumber(String number) {
    return '#$number';
  }

  @override
  String get fleetSortByTime => 'Po vremenu';

  @override
  String get fleetSortByComfort => 'Po komforu';

  @override
  String get fleetUnknownModel => 'Model nepoznat';

  @override
  String get fleetSectionComfort => 'Komfor';

  @override
  String get fleetSectionAmenities => 'U vozilu';

  @override
  String get fleetSectionDetails => 'Detalji';

  @override
  String get fleetAc => 'Klima';

  @override
  String get fleetNoAc => 'Bez klime';

  @override
  String get fleetLowFloor => 'Niski pod';

  @override
  String get fleetHighFloor => 'Stepenice na ulazu';

  @override
  String get fleetArticulated => 'Zglobni';

  @override
  String get fleetUsb => 'USB punjenje';

  @override
  String get fleetElectric => 'Električni';

  @override
  String get fleetHybrid => 'Hibrid';

  @override
  String get fleetCng => 'Na gas (CNG)';

  @override
  String get fleetTrolley => 'Trolejbus';

  @override
  String get fleetTram => 'Tramvaj';

  @override
  String get fleetDiesel => 'Dizel';

  @override
  String get fleetAge => 'Starost';

  @override
  String fleetAgeApprox(int years, int from, int to) {
    return '~$years god. (proizvedeno $from–$to)';
  }

  @override
  String fleetCapacity(int count) {
    return 'Prima ~$count';
  }

  @override
  String fleetLength(String meters) {
    return 'Dužina $meters m';
  }

  @override
  String fleetOperator(String name) {
    return 'Prevoznik: $name';
  }

  @override
  String fleetManufacturer(String value) {
    return 'Proizvođač: $value';
  }

  @override
  String get fleetComfortRetro => 'retro';

  @override
  String get fleetComfortOk => 'ok';

  @override
  String get fleetComfortComfy => 'komfor';

  @override
  String get fleetApproxNote =>
      '„~” označava vrednosti procenjene po prevozniku, ne potvrđene za baš ovo vozilo.';

  @override
  String get navCoverage => 'Pokrivenost';

  @override
  String get coverageFilterAll => 'Sve';

  @override
  String get coverageLegendTitle => 'Gustina prevoza';

  @override
  String get coverageLegendLow => 'ređe';

  @override
  String get coverageLegendHigh => 'češće';

  @override
  String get coverageUnavailable => 'Mapa pokrivenosti trenutno nije dostupna.';
}
