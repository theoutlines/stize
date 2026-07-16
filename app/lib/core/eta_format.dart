import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// Beyond this ETA, a minute count ("75 min") stops being legible — you no
/// longer do the arithmetic in your head — so show the clock arrival time
/// ("02:45", 24h) instead. Applied everywhere an ETA renders (arrivals list,
/// nearby, the collapsed Scheduled cell's times).
const int kFarEtaMinutes = 60;

/// The label for an arrival ETA:
///  * "Now" for a due/past arrival (≤ 0),
///  * "N min" while that stays readable (< [kFarEtaMinutes]),
///  * a 24h clock time for far-off arrivals (≥ [kFarEtaMinutes]).
///
/// [localeName] selects the locale's 24h format; [now] is injectable so the
/// far-ETA branch is deterministic under test. Mirrors the app's other
/// DateFormat use: locale-aware with a plain HH:mm fallback if a locale's date
/// data isn't loaded.
String etaLabel(
  AppLocalizations l10n,
  String localeName,
  int etaMinutes, {
  DateTime? now,
}) {
  if (etaMinutes >= kFarEtaMinutes) {
    final at = (now ?? DateTime.now()).add(Duration(minutes: etaMinutes));
    try {
      return DateFormat.Hm(localeName).format(at); // 24h HH:mm, locale-aware
    } catch (_) {
      return '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
    }
  }
  return etaMinutes <= 0 ? l10n.arrivalEtaNow : l10n.arrivalEtaMinutes(etaMinutes);
}
