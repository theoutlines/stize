/// Backend base URL. Override for local development with:
///   flutter run --dart-define=API_BASE_URL=http://localhost:8787
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://stigla-api.theoutlines.xyz',
);
