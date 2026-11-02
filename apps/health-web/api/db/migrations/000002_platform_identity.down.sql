-- 000002_platform_identity.down.sql
-- Reverses 000002. web_sessions references users, so it goes first.

DROP TABLE IF EXISTS web_sessions;
DROP TABLE IF EXISTS users;
