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
  String get searchMoreResults => 'Ещё результаты';

  @override
  String get panelCollapse => 'Свернуть панель';

  @override
  String get panelExpand => 'Развернуть панель';

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
  String get arrivalExpected => 'Ожидается';

  @override
  String get vehicleLost => 'Транспорт больше не отслеживается';

  @override
  String get followingVehicle => 'Следим';

  @override
  String get noLiveVehiclesOnMap =>
      'Нет машин с live-позицией — смотри список прибытий ниже.';

  @override
  String get nearbySearchHint => 'Фильтр линий рядом…';

  @override
  String nearbyDistanceMeters(int meters) {
    return '$meters м';
  }

  @override
  String get nearbyNeedsLocationTitle => 'Что ходит рядом';

  @override
  String get nearbyNeedsLocationSubtitle =>
      'Включите геолокацию, чтобы увидеть линии, на которые можно сесть поблизости.';

  @override
  String get nearbyEnableLocation => 'Моё местоположение';

  @override
  String get nearbyLoading => 'Ищем линии вокруг вас…';

  @override
  String get nearbyEmptyTitle => 'Рядом остановок нет';

  @override
  String get nearbyEmptySubtitle =>
      'Сейчас в пешей доступности от вас нет остановок.';

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
  String get arrivalScheduled => 'По расписанию';

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
  String get contextNearbyTitle => 'Рядом';

  @override
  String get aboutVehicle => 'Об этом транспорте';

  @override
  String get viewModelDetails => 'Подробнее о модели';

  @override
  String get backToVehicle => 'Вернуться к транспорту';

  @override
  String vehicleOffScreen(String line) {
    return '$line за экраном';
  }

  @override
  String get routeUnavailable => 'Маршрут недоступен для этой линии';

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
  String get liveUnavailableBanner =>
      'Живые данные временно недоступны — расписание';

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
  String get vehicleModeOnDemand => 'По запросу';

  @override
  String get vehicleModeAll => 'Весь транспорт';

  @override
  String get vehicleModeTooltip => 'Транспорт на карте';

  @override
  String vehicleModeSwitched(String mode) {
    return 'Транспорт на карте: $mode';
  }

  @override
  String get aboutTitle => 'О Stigla';

  @override
  String aboutRouteData(String date) {
    return 'Данные маршрутов: $date';
  }

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

  @override
  String get drawerFeedbackBannerLine =>
      'Приложение делает один человек — Иван из Белграда. Нашли баг? Напишите мне.';

  @override
  String get drawerFeedbackSheetTitle => 'Обратная связь';

  @override
  String get feedbackWriteToMe => 'Написать мне';

  @override
  String get feedbackWriteToMeSubtitle =>
      'Отправьте сообщение — баги, идеи, что угодно.';

  @override
  String get feedbackGithubIssues => 'GitHub Issues';

  @override
  String get feedbackGithubIssuesSubtitle =>
      'Для технических отчётов (публично).';

  @override
  String get feedbackFormTitle => 'Написать мне';

  @override
  String get feedbackMessageLabel => 'Ваше сообщение';

  @override
  String get feedbackMessageHint => 'Баг, идея, доброе слово…';

  @override
  String get feedbackContactLabel => 'Контакт (необязательно)';

  @override
  String get feedbackContactHint => 'Email или Telegram, если хотите ответ';

  @override
  String get feedbackSend => 'Отправить';

  @override
  String get feedbackSent => 'Спасибо — сообщение отправлено.';

  @override
  String get feedbackErrorGeneric => 'Не удалось отправить. Попробуйте позже.';

  @override
  String get feedbackErrorRateLimited =>
      'Подождите немного перед следующей отправкой.';

  @override
  String get feedbackEmptyValidation => 'Сначала напишите сообщение.';

  @override
  String get drawerLicenses => 'Лицензии открытого кода';

  @override
  String get drawerPrivacy => 'Политика конфиденциальности';

  @override
  String get drawerDonate => 'Поддержать Stigla';

  @override
  String get licensesLegalese =>
      'Stigla — свободное ПО под лицензией AGPL-3.0.';

  @override
  String get privacyTitle => 'Политика конфиденциальности';

  @override
  String get privacyIntro =>
      'Stigla приватна по умолчанию. Вот что именно она делает с данными — простыми словами.';

  @override
  String get privacyLocationTitle => 'Ваше местоположение';

  @override
  String get privacyLocationBody =>
      'Когда вы запрашиваете ближайшие остановки и транспорт, местоположение вашего устройства отправляется в наш API вместе с этим запросом, чтобы найти то, что рядом. Оно используется только для ответа на этот запрос и никогда не сохраняется на наших серверах.';

  @override
  String get privacyAnalyticsTitle => 'Анонимная статистика';

  @override
  String get privacyAnalyticsBody =>
      'Приложение может записывать анонимные события использования (например, что остановка была открыта), чтобы понимать, какие функции востребованы. В них нет идентификаторов и аккаунтов, и их нельзя связать с вами.';

  @override
  String get privacyTrackersTitle => 'Без рекламы и трекеров';

  @override
  String get privacyTrackersBody =>
      'В Stigla нет рекламы и нет сторонних рекламных или трекинговых SDK.';

  @override
  String get privacyFeedbackTitle => 'Отправленная вами обратная связь';

  @override
  String get privacyFeedbackBody =>
      'Если вы отправляете обратную связь, ваше сообщение — и указанный по желанию контакт — сохраняются, чтобы мы могли его прочитать и ответить вам. Больше вместе с ним ничего не собирается.';

  @override
  String get privacyOpenSourceTitle => 'Открытый код';

  @override
  String get privacyOpenSourceBody =>
      'Код Stigla открыт под лицензией AGPL-3.0, так что любой может проверить, как именно она работает.';
}
