-- Anti-Cheat System Schema
-- Execute this to create necessary tables for anti-cheat validation
-- Author: Anti-Cheat Design System
-- Created: 2026-10-02

-- 1. PENDING GAMES TABLE
-- Tracks in-flight sparkle claims before they're resolved
CREATE TABLE IF NOT EXISTS pending_games (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('fishing', 'blacksmith', 'murloc')),

  -- Challenge used for signing requests (not secret, sent to client)
  challenge TEXT NOT NULL UNIQUE,
  challenge_expires TIMESTAMP NOT NULL,

  created_at TIMESTAMP DEFAULT NOW(),
  created_at_epoch BIGINT NOT NULL, -- milliseconds for client comparison
  resolved_at TIMESTAMP,
  won BOOLEAN,

  CONSTRAINT challenge_min_length CHECK (LENGTH(challenge) >= 20)
);

CREATE INDEX idx_pending_games_user ON pending_games(user_id, created_at DESC);
CREATE INDEX idx_pending_games_challenge ON pending_games(challenge);
CREATE INDEX idx_pending_games_expires ON pending_games(challenge_expires)
  WHERE resolved_at IS NULL;

COMMENT ON TABLE pending_games IS 'Pending sparkle games awaiting resolution with cryptographic challenge';
COMMENT ON COLUMN pending_games.challenge IS 'Random challenge string used for HMAC-SHA256 signing (30s validity)';
COMMENT ON COLUMN pending_games.challenge_expires IS 'Challenge validity window (now + 30 seconds)';


-- 2. GAME EVENTS TABLE
-- Detailed log of all game attempts with flags
CREATE TABLE IF NOT EXISTS game_events (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pending_id UUID REFERENCES pending_games(id) ON DELETE SET NULL,

  game_type TEXT NOT NULL CHECK (game_type IN ('fishing', 'blacksmith', 'murloc')),
  won BOOLEAN NOT NULL,
  gold_awarded INT DEFAULT 0 CHECK (gold_awarded >= 0),

  -- Client-submitted timing data (for validation & replay analysis)
  client_timings JSONB,
  client_submit_time_ms BIGINT,
  server_receive_time_ms BIGINT DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000),

  -- Validation results
  flags TEXT[] DEFAULT ARRAY[]::TEXT[],
  severity TEXT DEFAULT 'LOW' CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH')),

  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_game_events_user ON game_events(user_id, created_at DESC);
CREATE INDEX idx_game_events_type_won ON game_events(game_type, won, created_at DESC);
CREATE INDEX idx_game_events_created ON game_events(created_at DESC);
CREATE INDEX idx_game_events_severity ON game_events(severity DESC, created_at DESC);

COMMENT ON TABLE game_events IS 'Complete log of game outcomes with anti-cheat flags';
COMMENT ON COLUMN game_events.flags IS 'Array of red flags detected: IMPOSSIBLE_SPEED, TAMPERING, etc.';
COMMENT ON COLUMN game_events.client_timings IS 'JSON array of click/interaction timestamps for admin review';


-- 3. CHEAT AUDIT LOG TABLE
-- Suspicious activity investigation trail
CREATE TABLE IF NOT EXISTS cheat_audit_log (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  event_type TEXT NOT NULL,
  -- Examples: SIGNATURE_MISMATCH, TAMPERING, IMPOSSIBLE_SPEED, SUPERHUMAN_CLICKS,
  --           REPLAY_ATTEMPT, TIME_SKEW, LATE_CLAIM, CLAIM_SPAM, WIN_RATE_SPIKE

  details JSONB DEFAULT '{}'::JSONB,
  flags TEXT[] DEFAULT ARRAY[]::TEXT[],
  severity TEXT NOT NULL CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH')),

  created_at TIMESTAMP DEFAULT NOW(),

  -- Investigation / resolution
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  review_notes TEXT,
  resolution TEXT CHECK (resolution IS NULL OR
                        resolution IN ('FALSE_POSITIVE', 'CONFIRMED_CHEAT', 'WARNING_ISSUED'))
);

CREATE INDEX idx_cheat_audit_user ON cheat_audit_log(user_id, created_at DESC);
CREATE INDEX idx_cheat_audit_severity ON cheat_audit_log(severity, created_at DESC);
CREATE INDEX idx_cheat_audit_event_type ON cheat_audit_log(event_type);
CREATE INDEX idx_cheat_audit_unreviewed ON cheat_audit_log(resolution, created_at DESC)
  WHERE resolution IS NULL;

COMMENT ON TABLE cheat_audit_log IS 'Audit trail for investigation of suspicious player activity';
COMMENT ON COLUMN cheat_audit_log.resolution IS 'NULL=pending, FALSE_POSITIVE=legit, CONFIRMED_CHEAT=cheater, WARNING_ISSUED=warned player';


-- 4. USER CHEAT SCORES TABLE
-- Running tally of suspicious activity per user
CREATE TABLE IF NOT EXISTS user_cheat_scores (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  total_points INT DEFAULT 0 CHECK (total_points >= 0),
  flag_count INT DEFAULT 0 CHECK (flag_count >= 0),

  status TEXT DEFAULT 'CLEAN' CHECK (status IN ('CLEAN', 'UNDER_REVIEW', 'SOFT_BAN')),
  -- CLEAN (0-49 pts): Normal
  -- UNDER_REVIEW (50-99 pts): Officer should investigate
  -- SOFT_BAN (100+ pts): Block from claiming new sparkles until reviewed

  last_flagged_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE user_cheat_scores IS 'Aggregated cheat score per user for soft-ban decisions';
COMMENT ON COLUMN user_cheat_scores.status IS 'CLEAN=0-49pts, UNDER_REVIEW=50-99pts, SOFT_BAN=100+pts';


-- 5. SPARKLE CLAIMS TRACKING
-- For rate-limiting (keep ~7 days of history)
CREATE TABLE IF NOT EXISTS sparkle_claims (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_sparkle_claims_user_time ON sparkle_claims(user_id, created_at DESC);

COMMENT ON TABLE sparkle_claims IS 'Rate-limiting tracker: 60 claims/hour normal, 100+ triggers review';


-- Ensure pgcrypto extension exists (needed for hmac)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Ensure pg_cron extension for scheduled cleanup (optional but recommended)
CREATE EXTENSION IF NOT EXISTS pg_cron;

GRANT SELECT, INSERT, UPDATE ON pending_games TO postgres;
GRANT SELECT, INSERT ON game_events TO postgres;
GRANT SELECT, INSERT, UPDATE ON cheat_audit_log TO postgres;
GRANT SELECT, INSERT, UPDATE ON user_cheat_scores TO postgres;
GRANT SELECT, INSERT ON sparkle_claims TO postgres;
