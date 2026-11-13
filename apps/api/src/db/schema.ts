/** Keep in sync with schema.sql — embedded so tsx/dist both migrate cleanly. */
export const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS library_entries (
  uid TEXT NOT NULL,
  title_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('owned', 'saved')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (uid, title_id, kind)
);

CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY,
  uid TEXT NOT NULL,
  title_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  anchor TEXT NOT NULL,
  location_id TEXT NOT NULL,
  position DOUBLE PRECISION NOT NULL DEFAULT 0,
  body_text TEXT,
  voice_duration_sec INT,
  voice_ref TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS notes_uid_title_idx ON notes (uid, title_id);

CREATE TABLE IF NOT EXISTS studio_drafts (
  id TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS studio_sales (
  id TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS catalogue_titles (
  id TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS catalogue_chapters (
  title_id TEXT NOT NULL,
  id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  PRIMARY KEY (title_id, id)
);

CREATE TABLE IF NOT EXISTS catalogue_tracks (
  title_id TEXT NOT NULL,
  id TEXT NOT NULL,
  title TEXT NOT NULL,
  duration_sec INT NOT NULL DEFAULT 0,
  media_url TEXT,
  media_name TEXT,
  sort_order INT NOT NULL DEFAULT 0,
  PRIMARY KEY (title_id, id)
);

CREATE TABLE IF NOT EXISTS admin_users (
  uid TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  display_name TEXT NOT NULL,
  market TEXT NOT NULL DEFAULT 'ZM',
  role TEXT NOT NULL DEFAULT 'listener',
  creator_status TEXT NOT NULL DEFAULT 'none',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  payload JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE UNIQUE INDEX IF NOT EXISTS admin_users_email_idx ON admin_users (lower(email));

CREATE TABLE IF NOT EXISTS admin_moderation (
  id TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  status TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS admin_payouts (
  id TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  status TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS admin_audit (
  id TEXT PRIMARY KEY,
  actor_email TEXT NOT NULL,
  action TEXT NOT NULL,
  target TEXT NOT NULL,
  at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reason TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS admin_audit_at_idx ON admin_audit (at DESC);

CREATE TABLE IF NOT EXISTS payment_intents (
  id TEXT PRIMARY KEY,
  uid TEXT NOT NULL,
  title_id TEXT NOT NULL,
  status TEXT NOT NULL,
  payload JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS payment_intents_uid_idx ON payment_intents (uid);

CREATE TABLE IF NOT EXISTS payment_webhook_events (
  event_id TEXT PRIMARY KEY,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;
