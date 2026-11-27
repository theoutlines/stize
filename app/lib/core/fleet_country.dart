/// Localized country-of-origin names for the codes used in the fleet data,
/// including historical ones (CS = Czechoslovakia, YU = Yugoslavia). Kept as a
/// small in-code table rather than 30+ arb keys; the UI label around it is
/// localized via l10n.
///
/// [code] may join several countries with "/" ("CN/BG").
String localizedFleetCountry(String code, String lang) {
  return code
      .split('/')
      .map((c) {
        final names = _countryNames[c.trim()];
        if (names == null) return c.trim();
        return names[lang] ?? names['en'] ?? c.trim();
      })
      .join('/');
}

const Map<String, Map<String, String>> _countryNames = {
  'BG': {'en': 'Bulgaria', 'sr': 'Bugarska'},
  'BY': {'en': 'Belarus', 'sr': 'Belorusija'},
  'CH': {'en': 'Switzerland', 'sr': 'Švajcarska'},
  'CN': {'en': 'China', 'sr': 'Kina'},
  'CS': {'en': 'Czechoslovakia', 'sr': 'Čehoslovačka'},
  'DE': {'en': 'Germany', 'sr': 'Nemačka'},
  'ES': {'en': 'Spain', 'sr': 'Španija'},
  'PL': {'en': 'Poland', 'sr': 'Poljska'},
  'RS': {'en': 'Serbia', 'sr': 'Srbija'},
  'TR': {'en': 'Turkey', 'sr': 'Turska'},
  'YU': {'en': 'Yugoslavia', 'sr': 'Jugoslavija'},
};
