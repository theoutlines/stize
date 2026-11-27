// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Serbian (`sr`).
class AppLocalizationsSr extends AppLocalizations {
  AppLocalizationsSr([String locale = 'sr']) : super(locale);

  @override
  String get appTitle => 'Stiže';

  @override
  String get navHome => 'Mapa';

  @override
  String get navMyStops => 'Moja stajališta';

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
  String get searchMoreResults => 'Više rezultata';

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
  String get vehicleScheduled => 'Po redu vožnje — nije pozicija uživo';

  @override
  String get vehicleLost => 'Vozilo se više ne prati';

  @override
  String get followingVehicle => 'Praćenje';


  @override
  String nearbyDistanceMeters(int meters) {
    return '$meters m';
  }

  @override
  String get nearbyNeedsLocationTitle => 'Šta ide u blizini';

  @override
  String get nearbyNeedsLocationSubtitle =>
      'Uključi lokaciju da vidiš linije koje možeš uhvatiti u blizini.';

  @override
  String get nearbyEnableLocation => 'Moja lokacija';

  @override
  String get nearbyLoading => 'Tražimo linije oko tebe…';

  @override
  String get nearbyEmptyTitle => 'Nema stajališta u blizini';

  @override
  String get nearbyEmptySubtitle =>
      'Trenutno nema stajališta na pešačkoj udaljenosti od tebe.';

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
  String get arrivalEtaMinutesUnit => 'min';

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
      zero: 'Na stajalištu',
    );
    return '$_temp0';
  }









  @override
  String get contextNearbyTitle => 'U blizini';

  @override
  String get backToVehicle => 'Nazad na vozilo';

  @override
  String get backTo => 'Nazad na';


  @override
  String get routeUnavailable => 'Ruta nije dostupna za ovu liniju';

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
  String get liveUnavailableBanner =>
      'Podaci uživo trenutno nisu dostupni — red vožnje';

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
  String get settingsThemeLight => 'Svetla';

  @override
  String get settingsThemeDark => 'Tamna';

  @override
  String get vehicleModeOnDemand => 'Na zahtev';

  @override
  String get vehicleModeAll => 'Sav prevoz';

  @override
  String get vehicleModeHint => 'Prevoz uživo';

  @override
  String get vehicleModeTooltip => 'Prevoz na mapi';

  @override
  String vehicleModeSwitched(String mode) {
    return 'Prevoz na mapi: $mode';
  }

  @override
  String get aboutTitle => 'O aplikaciji Stiže';

  @override
  String aboutRouteData(String date) {
    return 'Podaci o linijama: $date';
  }

  @override
  String get aboutDisclaimer =>
      'Nezvanična aplikacija. Nije povezana sa JKP Upravljanje javnim prevozom Beograd.';

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
  String fleetVehicleNumber(String number) {
    return '#$number';
  }

  @override
  String get fleetUnknownModel => 'Model nepoznat';


  @override
  String get fleetAc => 'Klima';







  @override
  String get fleetHybrid => 'Hibrid';











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
  String get drawerShareFeedback => 'Pošaljite utisak';

  @override
  String get drawerFeedbackSheetTitle => 'Utisci';


  @override
  String get feedbackWriteToMeSubtitle =>
      'Pošalji poruku: greške, ideje, bilo šta.';



  @override
  String get feedbackFormTitle => 'Piši mi';

  @override
  String get feedbackMessageLabel => 'Tvoja poruka';

  @override
  String get feedbackMessageHint => 'Greška, ideja, lepa reč…';

  @override
  String get feedbackContactLabel => 'Kontakt (opciono)';

  @override
  String get feedbackContactHint => 'Email ili Telegram, ako želiš odgovor';

  @override
  String get feedbackSend => 'Pošalji';

  @override
  String get feedbackSent => 'Hvala — poruka je poslata.';

  @override
  String get feedbackErrorGeneric => 'Slanje nije uspelo. Pokušaj kasnije.';

  @override
  String get feedbackErrorRateLimited =>
      'Sačekaj trenutak pre sledećeg slanja.';

  @override
  String get feedbackEmptyValidation => 'Prvo napiši poruku.';

  @override
  String get drawerLicenses => 'Licence otvorenog koda';

  @override
  String get drawerPrivacy => 'Politika privatnosti';

  @override
  String get licensesLegalese =>
      'Aplikacija Stiže je slobodan softver pod AGPL-3.0 licencom.';

  @override
  String get privacyTitle => 'Politika privatnosti';

  @override
  String get privacyIntro =>
      'Aplikacija Stiže je privatna podrazumevano. Evo tačno šta radi sa podacima, jednostavnim rečima.';

  @override
  String get privacyLocationTitle => 'Tvoja lokacija';

  @override
  String get privacyLocationBody =>
      'Kada zatražiš obližnja stajališta i vozila, lokacija tvog uređaja se šalje našem API-ju uz taj zahtev da bismo pronašli šta je u blizini. Koristi se samo za odgovor na taj zahtev i nikada se ne čuva na našim serverima.';

  @override
  String get privacyAnalyticsTitle => 'Anonimna upotreba';

  @override
  String get privacyAnalyticsBody =>
      'Aplikacija može beležiti anonimne događaje korišćenja (na primer, da je stajalište otvoreno) da bismo razumeli koje se funkcije koriste. Nemaju identifikatore ni naloge i ne mogu se povezati s tobom.';

  @override
  String get privacyTrackersTitle => 'Bez reklama i trekera';

  @override
  String get privacyTrackersBody =>
      'Aplikacija Stiže ne prikazuje reklame i ne sadrži oglašivačke ni treking SDK-ove trećih strana.';

  @override
  String get privacyFeedbackTitle => 'Utisci koje pošalješ';

  @override
  String get privacyFeedbackBody =>
      'Ako pošalješ utiske, tvoja poruka — i opcioni kontakt koji navedeš — čuvaju se da bismo je pročitali i odgovorili ti. Ništa drugo se uz nju ne prikuplja.';

  @override
  String get privacyServicesTitle => 'Servisi sa kojih se aplikacija učitava';

  @override
  String get privacyServicesBody =>
      'Kao i svaki sajt, aplikacija neke delove učitava sa drugih servisa, koji pri tom vide vašu IP adresu: mapa za oblast koju gledate dolazi sa MapTiler-a, fontovi i delovi pokretača aplikacije sa Google-a (gstatic.com), a aplikaciju i njen API isporučuje Cloudflare. Nijedan od njih od nas ne dobija vašu lokaciju niti podatke o nalogu.';

  @override
  String get privacyOpenSourceTitle => 'Otvoren kod';

  @override
  String get privacyOpenSourceBody =>
      'Kod aplikacije Stiže je otvoren pod AGPL-3.0 licencom, tako da svako može proveriti kako tačno radi.';

  @override
  String jamStopBannerTitle(String line) {
    return 'Tramvaji $line stoje duže nego obično — moguće kašnjenje';
  }

  @override
  String jamSubstitutionNotice(String line) {
    return 'Na liniji $line umesto tramvaja saobraćaju autobusi';
  }

  @override
  String get jamModeTooltip => 'Prikaži zastoje';

  @override
  String jamNearbyDelay(String line) {
    return 'Moguće kašnjenje na liniji $line';
  }

  @override
  String get jamAffectedStopsTitle => 'Pogođene stanice';

  @override
  String get jamFollowAhead => 'Moguće kašnjenje ispred na trasi';


  @override
  String get arrivalTerminus => 'Konačna';

  @override
  String get stopMore => 'Više';

  @override
  String get stopReportProblem => 'Prijavi problem';

  @override
  String get stopInMyStops => 'U Mojim stajalištima';

  @override
  String get stopReportTitle => 'Šta nije u redu?';

  @override
  String get stopReportNotHere => 'Stanica nije ovde ili je na drugom mestu';

  @override
  String get stopReportWrongType =>
      'Pogrešan tip (autobus, tramvaj, trolejbus)';

  @override
  String get stopReportWrongLines => 'Pogrešne linije';

  @override
  String get stopReportArrivalsWrong => 'Dolasci se ne poklapaju sa stvarnošću';

  @override
  String get stopReportWrongName => 'Pogrešan naziv';

  @override
  String get stopReportOther => 'Nešto drugo';

  @override
  String get stopReportOtherLabel => 'Napišite šta nije u redu';

  @override
  String get stopReportOtherHint => 'Potrebno za „Nešto drugo“';

  @override
  String get stopReportPrivacy =>
      'Dobijamo stanicu i njene linije. Ne vašu lokaciju.';

  @override
  String get stopReportSend => 'Pošalji';

  @override
  String get stopReportSentTitle => 'Hvala, primili smo';

  @override
  String stopReportSentBody(String what, String stop) {
    return 'Proverićemo „$what“ na stanici $stop i ispraviti podatke. Ne treba ništa više da radite.';
  }

  @override
  String get stopReportAlreadyTitle => 'Već poslato danas';

  @override
  String stopReportAlreadyBody(String what) {
    return 'Danas ste nam već javili „$what“ za ovu stanicu. Jedna prijava je dovoljna: proverićemo.';
  }

  @override
  String get stopReportBack => 'Nazad na stanicu';

  @override
  String get stopReportTooFast => 'Sačekajte minut pre sledeće prijave.';

  @override
  String get stopReportFailed =>
      'Slanje nije uspelo. Proverite vezu i pokušajte ponovo.';

  @override
  String get aboutDataSource =>
      'Stanice, linije i redovi vožnje: otvoreni podaci Grada Beograda (Sekretarijat za javni prevoz), objavljeni na data.gov.rs pod licencom za otvorene podatke Republike Srbije. Podatke prepakujemo za aplikaciju. Mapa: MapTiler, saradnici OpenStreetMap-a.';

  @override
  String get menuSupport => 'Podrži Stiže';

  @override
  String get menuClose => 'Zatvori meni';

  @override
  String get settingsAuto => 'Auto';

  @override
  String get settingsAutoHint =>
      'Auto prati podešavanja telefona. Prevoz na mapi se uključuje dugmetom slojeva na mapi.';

  @override
  String get guideTitle => 'Vodič kroz Beograd';

  @override
  String get guideFree =>
      'Gradski prevoz je besplatan: autobusi, tramvaji, trolejbusi';

  @override
  String get guideGettingAround => 'Kako se kretati';

  @override
  String get guideFromAirport => 'Sa aerodroma';

  @override
  String get guideFromAirportSub => 'Linije 72, A1, 600, 607 · noću 72N';

  @override
  String get guideFromBusStation => 'Sa autobuske stanice';

  @override
  String get guideFromBusStationSub =>
      'Beogradska autobuska stanica, Novi Beograd';

  @override
  String get guideFromRailStation => 'Sa železničke stanice';

  @override
  String get guideFromRailStationSub => 'Beograd Centar (Prokop)';

  @override
  String get guideReadStop => 'Kako čitati stanicu';

  @override
  String get guideReadStopSub => 'Minuti uživo i vreme po redu vožnje';

  @override
  String get guideReadStopLive =>
      'Veliki minuti su uživo: vozilo je na putu i vidimo ga preko GPS-a.';

  @override
  String get guideReadStopScheduled =>
      'Vreme u satima je po redu vožnje: za taj polazak još nema signala uživo.';

  @override
  String get guideReadStopStar =>
      'Dodirnite zvezdicu da sačuvate stanicu u Moje stanice.';

  @override
  String get guideReadStopNight => 'Linije sa slovom N saobraćaju noću.';

  @override
  String get guidePlaces => 'Mesta koja ljudi traže';

  @override
  String get guidePlacesSub => 'Tvrđava, trgovi, stanice, Ada';

  @override
  String get guideNowLabel => 'Upravo sada';

  @override
  String get guideExpoTitle => 'Expo 2027 u Beogradu';

  @override
  String get guideExpoDays => 'dana do otvaranja';

  @override
  String get guideExpoSub =>
      'Od 15. maja do 15. avgusta 2027. Linije za Expo dodajemo čim ih grad objavi.';

  @override
  String get guideNightTitle => 'Saobraćaju noćne linije';

  @override
  String get guideNightSub =>
      'Posle ponoći saobraćaju noćne linije. Njihovi brojevi se završavaju na N.';

  @override
  String get guideStripNight => 'Saobraćaju noćne linije';

  @override
  String get guideStripNightSub => 'Šta vozi posle ponoći';

  @override
  String get guideStripNew => 'Prvi put u Beogradu? Otvorite vodič';

  @override
  String get guideStripNewSub => 'Besplatan prevoz, aerodrom, noćne linije';

  @override
  String get guideStripAirport => 'Na aerodromu ste';

  @override
  String get guideStripAirportSub => 'Do grada: 72, A1, 600';

  @override
  String get guideStripBusStation => 'Na autobuskoj stanici ste';

  @override
  String get guideStripBusStationSub =>
      'Gradske linije polaze sa stajališta kod izlaza';

  @override
  String get guideStripRailStation => 'Na stanici Beograd Centar ste';

  @override
  String get guideStripRailStationSub => 'Gradske linije: 34, 36, 600';

  @override
  String arrivalThenTo(String place) {
    return 'Zatim do $place';
  }

  @override
  String get locateMeTooltip => 'Prikaži gde sam';

  @override
  String get nearbyAroundYou => 'Oko vas';

  @override
  String get cityTitle => 'Grad';

  @override
  String get cityHeadline => 'Kako radi prevoz u Beogradu';

  @override
  String get citySubtitle => 'Na osnovu dolazaka koje su videli naši korisnici';

  @override
  String get cityKpiDelay => 'Prosečno kašnjenje';

  @override
  String get cityKpiInterval => 'Uobičajeni interval';

  @override
  String get cityKpiLines => 'Viđene linije';

  @override
  String get cityKpiArrivals => 'Viđeni dolasci';

  @override
  String cityMin(int n) {
    return '$n min';
  }

  @override
  String get cityOnTime => 'na vreme';

  @override
  String cityLateBy(int n) {
    return 'kasni $n min';
  }

  @override
  String cityEarlyBy(int n) {
    return 'ranije $n min';
  }

  @override
  String get cityHeatTitle => 'Kada kasni';

  @override
  String get cityHeatSubtitle => 'Prosečno kašnjenje po danu i satu';

  @override
  String get cityLegendLow => 'na vreme';

  @override
  String get cityLegendHigh => 'često kasni';

  @override
  String cityHeatWorst(String day, int hour, int min) {
    return 'Najgore: $day u $hour:00, oko $min min kašnjenja.';
  }

  @override
  String cityHeatCell(String day, int hour, int next) {
    return '$day $hour:00–$next:00';
  }

  @override
  String cityHeatCellCount(int n) {
    return 'dolazaka: $n';
  }

  @override
  String get cityHeatFew => 'premalo dolazaka';

  @override
  String get cityLinesTitle => 'Linije';

  @override
  String get cityLinesSubtitle =>
      'Veličina: viđeni dolasci · broj: prosečno kašnjenje';

  @override
  String cityLinesSummary(String best, String worst) {
    return '$best je najtačnija linija. $worst najviše kasni.';
  }

  @override
  String get cityLegendBest => 'najbolja';

  @override
  String get cityLegendWorst => 'najgora';

  @override
  String get cityLegendThin => 'premalo dolazaka za ocenu';

  @override
  String get cityIntervalsTitle => 'Najduži stvarni intervali';

  @override
  String get cityIntervalsSubtitle => 'Uveče od 21 do 1, prosečno čekanje';

  @override
  String get cityNote =>
      'Vidimo samo stanice koje ljudi otvaraju, u satima kada ih otvaraju. Linije sa premalo dolazaka ne rangiramo.';

  @override
  String get cityEmptyTitle => 'Još nema dovoljno dolazaka';

  @override
  String cityEmptyBody(int min) {
    return 'Statistika se pojavljuje kada vidimo bar $min dolazaka.';
  }

  @override
  String get cityLineUsual => 'Obično u ovo vreme';

  @override
  String cityLineEvery(int n) {
    return 'na svakih $n min';
  }

  @override
  String get cityLineHeatSubtitle => 'Ova linija, po danu i satu';

  @override
  String cityLineThinBody(int n, int min) {
    return 'Videli smo $n dolazaka ove linije. Statistika se pojavljuje posle $min.';
  }

  @override
  String get cityLineNoHour => 'nema podataka za ovaj sat';

  @override
  String cityLinesBestOnly(String best) {
    return '$best je najtačnija linija; nijedna od prometnih linija ne kasni primetno.';
  }

  @override
  String arrivalNextList(String times) {
    return 'još $times min';
  }

  @override
  String get arrivalStartsHere => 'Polazi odavde';

  @override
  String get arrivalByTimetable => 'Po redu vožnje';

  @override
  String followStopsTo(int count, String stop) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$stop za $count stanica',
      few: '$stop za $count stanice',
      one: '$stop za $count stanicu',
    );
    return '$_temp0';
  }

  @override
  String followAtStop(String stop) {
    return 'Na stanici $stop';
  }

  @override
  String followNextStop(String stop) {
    return 'Sledeća: $stop';
  }

  @override
  String followStuck(int minutes) {
    return 'U zastoju · $minutes min';
  }

  @override
  String get followYourStop => 'Vaša stanica';

  @override
  String fleetChipAge(int years) {
    return '$years god.';
  }

  @override
  String fleetChipCapacity(int count) {
    return '~$count putnika';
  }

  @override
  String fleetChipComfort(String word) {
    return 'Udobnost: $word';
  }

  @override
  String get fleetChipSteps => 'Stepenice';

  @override
  String get fleetChipLowFloor => 'Niskopodni';

  @override
  String fleetMadeBy(String value) {
    return 'Proizvođač $value';
  }

  @override
  String fleetOperatorShort(String name) {
    return 'Prevoznik $name';
  }

  @override
  String fleetPhotoShort(String author, String license) {
    return 'Foto: $author, $license';
  }

  @override
  String get close => 'Zatvori';

  @override
  String get fleetChipArticulated => 'Zglobni';

  @override
  String get fleetChipAc => 'Klima';

  @override
  String get fleetChipNoAc => 'Bez klime';

  @override
  String get nearbyThisPoint => 'Oko ove tačke';
}
