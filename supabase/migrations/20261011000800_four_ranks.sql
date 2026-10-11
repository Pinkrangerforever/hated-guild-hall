-- Migration: Four ranks - Member -> Raider -> Officer, plus Raid Leader (protected, the owner only)
-- Purpose:
--   * profiles.role allows 'raider' (Raid Leader stays the separate protected flag).
--   * set_member_rank(user, rank): Officers may move people between Member and Raider; only the
--     Raid Leader may make or remove Officers. Nobody can change the Raid Leader or their own rank.
--   * Players can no longer change roles with a direct table update (the trigger sends them here).
--   * is_officer() unchanged: Raiders get Member permissions until we decide what they unlock.
-- Date: 2026-10-11
-- Reverse: restore protect_role_column from 20261010000800; DROP FUNCTION set_member_rank(uuid, text);
--          UPDATE profiles SET role = 'member' WHERE role = 'raider'; restore the old role check.

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role = ANY (ARRAY['member', 'raider', 'officer']));

CREATE OR REPLACE FUNCTION public.protect_role_column()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
begin
  -- Our own server functions (SECURITY DEFINER, owned by postgres), migrations and the SQL editor
  -- are trusted. Only direct API requests from players are checked below.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if old.protected = true then
    if new.role is distinct from old.role or new.protected is distinct from old.protected then
      raise exception 'This account is protected and can only be changed by the Discord sync process';
    end if;
  end if;

  -- Ranks change only through set_member_rank (which enforces who may promote whom)
  if new.role is distinct from old.role then
    raise exception 'Ranks can only be changed with set_member_rank';
  end if;

  if new.protected is distinct from old.protected then
    raise exception 'Protected status can only be changed by the Discord sync process';
  end if;

  if new.gold is distinct from old.gold or new.last_gold_claim_at is distinct from old.last_gold_claim_at then
    if not (public.is_officer() or (select p.discord_rank_level from public.profiles p where p.id = auth.uid()) = 1) then
      raise exception 'Gold can only be changed by the sparkle claim process or by Raid Leaders';
    end if;
  end if;

  if new.food is distinct from old.food
     or new.wood is distinct from old.wood
     or new.food_earned_total is distinct from old.food_earned_total
     or new.food_spent_total is distinct from old.food_spent_total
     or new.wood_earned_total is distinct from old.wood_earned_total
     or new.wood_spent_total is distinct from old.wood_spent_total
     or new.gold_earned_total is distinct from old.gold_earned_total
     or new.gold_spent_total is distinct from old.gold_spent_total
     or new.discord_rank_level is distinct from old.discord_rank_level then
    raise exception 'Resources, totals and rank can only be changed by the game itself';
  end if;

  return new;
end;
$$;

CREATE OR REPLACE FUNCTION public.set_member_rank(p_user_id UUID, p_role TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me UUID := auth.uid();
  v_my_role TEXT;
  v_my_protected BOOLEAN;
  v_target RECORD;
BEGIN
  IF v_me IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not signed in');
  END IF;
  IF p_role NOT IN ('member', 'raider', 'officer') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unknown rank');
  END IF;
  SELECT pr.role, COALESCE(pr.protected, false) INTO v_my_role, v_my_protected FROM profiles pr WHERE pr.id = v_me;
  SELECT pr.id, pr.role, COALESCE(pr.protected, false) AS protected, pr.character_name INTO v_target
  FROM profiles pr WHERE pr.id = p_user_id FOR UPDATE;
  IF v_target.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Player not found');
  END IF;
  IF v_target.protected OR p_user_id = v_me THEN
    RETURN jsonb_build_object('success', false, 'error', 'That rank can''t be changed here');
  END IF;

  IF NOT v_my_protected THEN
    -- Officers: only between Member and Raider, and never on another Officer
    IF v_my_role <> 'officer' OR v_target.role = 'officer' OR p_role = 'officer' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Only the Raid Leader can do that');
    END IF;
  END IF;

  UPDATE profiles SET role = p_role WHERE id = p_user_id;
  RETURN jsonb_build_object('success', true, 'role', p_role, 'character_name', v_target.character_name);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_member_rank(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_member_rank(UUID, TEXT) TO authenticated;
