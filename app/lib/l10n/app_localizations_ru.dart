// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Stigla';

  @override
  String get navHome => 'Карта';

  @override
  String get navMyStops => 'Мои остановки';

  @override
  String get navIdeas => 'Идеи';

  @override
  String get navAbout => 'О приложении';

  @override
  String get ideasEmptyTitle => 'Пока нет идей';

  @override
  String get ideasEmptySubtitle => 'Стань первым, кто что-то предложит.';

  @override
  String get ideaInputHint => 'Что улучшить в Stigla?';

  @override
  String get ideaSubmit => 'Предложить';

  @override
  String get ideaRateLimited =>
      'Можно предложить только одну идею за раз — попробуй через несколько минут.';

  @override
  String ideaVotesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count голосов',
      many: '$count голосов',
      few: '$count голоса',
      one: '$count голос',
      zero: 'Пока нет голосов',
    );
    return '$_temp0';
  }

  @override
  String get ideaCommentsTitle => 'Комментарии';

  @override
  String get ideaCommentInputHint => 'Добавить комментарий…';

  @override
  String get ideaCommentSubmit => 'Отправить';

  @override
  String get ideaCommentsEmpty => 'Пока нет комментариев.';

  @override
  String get myStopsEmptyTitle => 'Пока нет избранных остановок';

  @override
  String get myStopsEmptySubtitle =>
      'Найди остановку, улицу или линию и добавь сюда.';

  @override
  String get searchHint => 'Остановка, улица или линия…';

  @override
  String get searchNoResults =>
      'Ничего не нашлось. Может, стоит попробовать иначе написать?';

  @override
  String get locationDenied =>
      'Доступ к геолокации запрещён. Разрешите его в браузере или настройках, чтобы видеть себя на карте.';

  @override
  String get locationServicesOff =>
      'Службы геолокации выключены. Включите их в настройках устройства.';

  @override
  String get locationTimeout =>
      'Не удалось определить местоположение вовремя. Проверьте связь и попробуйте снова.';

  @override
  String get locationUnavailable =>
      'Местоположение сейчас недоступно. Попробуйте через минуту.';

  @override
  String get nearbyStopsTitle => 'Остановки рядом';

  @override
  String get nearbyStopsEmpty =>
      'Включи геолокацию или поищи остановку, улицу или линию выше.';

  @override
  String get mapZoomInForVehicles =>
      'Приблизьте карту, чтобы увидеть транспорт';

  @override
  String get vehicleScheduled => 'По расписанию — не живая позиция';

  @override
  String get stopUpdatedJustNow => 'Обновлено только что';

  @override
  String stopUpdatedSecondsAgo(int seconds) {
    return 'Обновлено $seconds сек назад';
  }

  @override
  String stopUpdatedMinutesAgo(int minutes) {
    return 'Обновлено $minutes мин назад';
  }

  @override
  String arrivalEtaMinutes(int minutes) {
    return '$minutes мин';
  }

  @override
  String get arrivalEtaNow => 'Сейчас';

  @override
  String arrivalStopsAway(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count остановок',
      many: '$count остановок',
      few: '$count остановки',
      one: '$count остановка',
      zero: 'здесь',
    );
    return '$_temp0';
  }

  @override
  String get vehicleMoving => 'В движении';

  @override
  String get vehicleStuck => 'Похоже, стоит';

  @override
  String get vehicleNextStop => 'Следующая остановка';

  @override
  String get vehicleUpcomingStops => 'Дальше по маршруту';

  @override
  String get vehicleYourStop => 'ваша остановка';

  @override
  String get vehicleEtaApprox => 'Время прибытия ориентировочное';

  @override
  String get vehicleShowRoute => 'Показать маршрут на карте';

  @override
  String vehicleEtaMinutesApprox(int minutes) {
    return '≈ $minutes мин';
  }

  @override
  String get emptyArrivalsTitle => 'Пока тихо на этой остановке';

  @override
  String get emptyArrivalsSubtitle => 'Транспорт скоро появится.';

  @override
  String get noNetworkTitle => 'Кажется, интернет отвалился';

  @override
  String get noNetworkSubtitle =>
      'Проверь связь и потяни вниз, чтобы попробовать снова.';

  @override
  String get loadingArrivals => 'Смотрим, что едет…';

  @override
  String get serviceKilledTitle => 'Мы ненадолго остановились';

  @override
  String get serviceKilledSubtitle => 'Скоро вернёмся.';

  @override
  String get unknownStopTitle => 'Не могу найти эту остановку';

  @override
  String get unknownStopSubtitle =>
      'Возможно, её переименовали или убрали из расписания.';

  @override
  String get retry => 'Попробовать снова';

  @override
  String get addToFavorites => 'Добавить в мои остановки';

  @override
  String get removeFromFavorites => 'Убрать из моих остановок';

  @override
  String get pinnedRenameTitle => 'Своё название';

  @override
  String get pinnedCustomNameHint => 'напр. Дом, Работа';

  @override
  String get pinnedUseDefaultName => 'Стандартное имя';

  @override
  String get pinLineTooltip => 'Закрепить линию';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsTheme => 'Тема';

  @override
  String get settingsThemeSystem => 'Как в системе';

  @override
  String get settingsThemeLight => 'Светлая';

  @override
  String get settingsThemeDark => 'Тёмная';

  @override
  String get aboutTitle => 'О Stigla';

  @override
  String get aboutDisclaimer =>
      'Неофициальное приложение. Не связано с JKP Upravljanje javnim prevozom Beograd.';

  @override
  String get aboutDescription =>
      'Stigla показывает прибытие транспорта Белграда в реальном времени. Сделано для личного использования.';

  @override
  String get lineFilterAll => 'Все линии';

  @override
  String get alertUpcomingLabel => 'Скоро изменение';

  @override
  String get alertActiveLabel => 'Изменение маршрута';

  @override
  String get alertReadMore => 'Подробнее';

  @override
  String get alertsBannerTitle => 'Изменения по транспорту';

  @override
  String get vehicleTypeBus => 'Автобус';

  @override
  String get vehicleTypeTram => 'Трамвай';

  @override
  String get vehicleTypeTrolleybus => 'Троллейбус';

  @override
  String fleetAgeYears(int years) {
    return '$years г';
  }

  @override
  String fleetVehicleNumber(String number) {
    return '№$number';
  }

  @override
  String get fleetSortByTime => 'По времени';

  @override
  String get fleetSortByComfort => 'По комфорту';

  @override
  String get fleetUnknownModel => 'Модель неизвестна';

  @override
  String get fleetSectionComfort => 'Комфорт';

  @override
  String get fleetSectionAmenities => 'В салоне';

  @override
  String get fleetSectionDetails => 'Подробности';

  @override
  String get fleetAc => 'Кондиционер';

  @override
  String get fleetNoAc => 'Без кондиционера';

  @override
  String get fleetLowFloor => 'Низкий пол';

  @override
  String get fleetHighFloor => 'Ступеньки на входе';

  @override
  String get fleetArticulated => 'Гармошка';

  @override
  String get fleetUsb => 'USB-зарядка';

  @override
  String get fleetElectric => 'Электро';

  @override
  String get fleetHybrid => 'Гибрид';

  @override
  String get fleetCng => 'На газе (CNG)';

  @override
  String get fleetTrolley => 'Троллейбус';

  @override
  String get fleetTram => 'Трамвай';

  @override
  String get fleetDiesel => 'Дизель';

  @override
  String get fleetAge => 'Возраст';

  @override
  String fleetAgeApprox(int years, int from, int to) {
    return '~$years г (выпуск $from–$to)';
  }

  @override
  String fleetCapacity(int count) {
    return 'Вмещает ~$count';
  }

  @override
  String fleetLength(String meters) {
    return 'Длина $meters м';
  }

  @override
  String fleetOperator(String name) {
    return 'Перевозчик: $name';
  }

  @override
  String fleetManufacturer(String value) {
    return 'Производитель: $value';
  }

  @override
  String get fleetComfortRetro => 'ретро';

  @override
  String get fleetComfortOk => 'норм';

  @override
  String get fleetComfortComfy => 'комфорт';

  @override
  String get fleetApproxNote =>
      '«~» — значения оценены по перевозчику, а не подтверждены для этой конкретной машины.';

  @override
  String get navCoverage => 'Покрытие';

  @override
  String get coverageFilterAll => 'Все';

  @override
  String get coverageLegendTitle => 'Плотность транспорта';

  @override
  String get coverageLegendLow => 'реже';

  @override
  String get coverageLegendHigh => 'чаще';

  @override
  String get coverageUnavailable => 'Карта покрытия сейчас недоступна.';
}
