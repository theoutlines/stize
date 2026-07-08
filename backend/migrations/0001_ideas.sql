CREATE TABLE ideas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  text TEXT NOT NULL,
  created_at TEXT NOT NULL,
  hidden INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE idea_votes (
  idea_id INTEGER NOT NULL REFERENCES ideas(id),
  device_id TEXT NOT NULL,
  PRIMARY KEY (idea_id, device_id)
);

CREATE TABLE idea_comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  idea_id INTEGER NOT NULL REFERENCES ideas(id),
  device_id TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX idx_idea_votes_idea_id ON idea_votes(idea_id);
CREATE INDEX idx_idea_comments_idea_id ON idea_comments(idea_id);
