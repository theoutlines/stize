import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stize/data/local/settings_store.dart';
import 'package:stize/l10n/app_localizations.dart';

/// Russian was dropped on 2026-11-22 (Uncut Sans ships no Cyrillic). Two
/// resolution rules must hold afterwards:
///   - a previously *saved* `ru` choice falls back to "follow the system";
///   - a `ru` *system* locale resolves to English, the first supported locale.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a saved Russian locale is cleared back to System', () async {
    SharedPreferences.setMockInitialValues({'settings_locale_code': 'ru'});
    final settings = await SettingsStore().load();
    expect(settings.localeCode, isNull);

    // The stale value is also wiped from storage, not just ignored.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings_locale_code'), isNull);
  });

  test('a saved supported locale survives load', () async {
    SharedPreferences.setMockInitialValues({'settings_locale_code': 'sr'});
    final settings = await SettingsStore().load();
    expect(settings.localeCode, 'sr');
  });

  test('a Russian system locale resolves to English', () {
    final resolved = basicLocaleListResolution(const [
      Locale('ru'),
    ], AppLocalizations.supportedLocales);
    expect(resolved, const Locale('en'));
  });

  test('a Serbian system locale still resolves to Serbian', () {
    final resolved = basicLocaleListResolution(const [
      Locale('sr'),
    ], AppLocalizations.supportedLocales);
    expect(resolved, const Locale('sr'));
  });
}
