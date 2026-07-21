/// Canonical outward links for the app. The public repository URL is the git
/// origin (`github.com/theoutlines/stize`); the private feedback-triage repo is
/// intentionally NOT referenced here (it's a backend secret path).

/// The public source repository (AGPL-3.0). Used by the licenses page header and
/// the "GitHub Issues" drawer action. The repo is renamed stigla → stize at the
/// end of the rename task; GitHub 301-redirects the old path, so old links keep
/// working.
const String kRepoUrl = 'https://github.com/theoutlines/stize';

/// Public issue tracker for technical users.
const String kRepoIssuesUrl = '$kRepoUrl/issues';

/// The app's own license identifier (SPDX).
const String kAppLicense = 'AGPL-3.0';
