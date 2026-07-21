/// Backend base URL. Override for local development with:
///   flutter run --dart-define=API_BASE_URL=http://localhost:8787
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.stize.app',
);

/// Which environment this build targets: "production" (default) or "staging".
/// The staging build is produced with `--dart-define=ENVIRONMENT=staging` and
/// shows a visible STAGING marker so it isn't mistaken for production.
const String appEnvironment = String.fromEnvironment(
  'ENVIRONMENT',
  defaultValue: 'production',
);

bool get isStaging => appEnvironment == 'staging';

/// How often the client re-polls live data (arrivals, vehicles). Fixed at 30s
/// to match the backend's per-key SWR cache: polling faster just re-reads the
/// same cached positions, which the movement heuristic misreads as "stuck", and
/// slower gives no benefit. Not user-configurable (F9) — keep it here as the
/// single source of truth, and in sync with the backend cache TTL.
const Duration kLiveRefreshInterval = Duration(seconds: 30);
