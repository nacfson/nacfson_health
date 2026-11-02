-- 000002_platform_identity.up.sql
-- Platform identity for health-web (spec 001-health-web-gateway-auth).
--
--   users        - one health-web project account per platform identity
--                  (issuer, subject). The id is the tenant key every user-owned
--                  table already stores in user_id. No email or profile identity
--                  data is kept here (AUTH-01: email is never an identifier).
--   web_sessions - server-side browser sessions. The browser only holds a random
--                  token in __Host-health_session; this table maps sha256(token)
--                  to the gateway's opaque session handle.
--
-- Additive only: no existing table changes.

CREATE TABLE IF NOT EXISTS users (
    id           UUID        PRIMARY KEY,
    issuer       TEXT        NOT NULL,
    subject      TEXT        NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_issuer_subject_key UNIQUE (issuer, subject),
    CONSTRAINT users_issuer_not_blank CHECK (btrim(issuer) <> ''),
    CONSTRAINT users_subject_not_blank CHECK (btrim(subject) <> '')
);

CREATE TABLE IF NOT EXISTS web_sessions (
    id_hash        BYTEA       PRIMARY KEY,
    user_id        UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    issuer         TEXT        NOT NULL,
    subject        TEXT        NOT NULL,
    session_handle TEXT        NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at     TIMESTAMPTZ NOT NULL,
    CONSTRAINT web_sessions_id_hash_len CHECK (octet_length(id_hash) = 32)
);

CREATE INDEX IF NOT EXISTS web_sessions_expires_at_idx ON web_sessions (expires_at);
CREATE INDEX IF NOT EXISTS web_sessions_user_id_idx ON web_sessions (user_id);
