/// Backend base URL. Override for local development with:
///   flutter run --dart-define=API_BASE_URL=http://localhost:8787
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://stigla-api.theoutlines.xyz',
);

/// Which environment this build targets: "production" (default) or "staging".
/// The staging build is produced with `--dart-define=ENVIRONMENT=staging` and
/// shows a visible STAGING marker so it isn't mistaken for production.
const String appEnvironment = String.fromEnvironment(
  'ENVIRONMENT',
  defaultValue: 'production',
);

bool get isStaging => appEnvironment == 'staging';
