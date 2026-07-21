-- In-app feedback submissions (drawer footer → POST /api/v1/feedback).
-- D1 is the DURABLE primary store; a best-effort GitHub issue is created on top
-- for triage but never gates or replaces this row. `contact` is optional (the
-- user may leave it blank); app_version/platform/locale are attached by the
-- client automatically, not typed. Timestamps are ISO strings, like `ideas`.
CREATE TABLE feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message TEXT NOT NULL,
  contact TEXT,
  app_version TEXT,
  platform TEXT,
  locale TEXT,
  created_at TEXT NOT NULL
);
