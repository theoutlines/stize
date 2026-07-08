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
  String get navMyStops => 'Мои остановки';

  @override
  String get navSearch => 'Поиск';

  @override
  String get navAbout => 'О приложении';

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
  String get settingsRefreshInterval => 'Интервал обновления';

  @override
  String settingsRefreshIntervalSeconds(int seconds) {
    return '$seconds сек';
  }

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
  String get vehicleTypeBus => 'Автобус';

  @override
  String get vehicleTypeTram => 'Трамвай';

  @override
  String get vehicleTypeTrolleybus => 'Троллейбус';
}
