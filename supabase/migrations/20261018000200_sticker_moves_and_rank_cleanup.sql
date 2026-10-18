-- Migration: sticker moves, and removing the old discord-rank permissions / officer gold edits
-- Purpose:
--   * update_sticker_position: Officers (and the Raid Leader) can move any sticker. A member can move only their own
--     sticker, and not on top of another one (closer than 12% of the board to another sticker's centre - the same
--     rule the board enforces while dragging). Deleting stays Raid Leader only (delete_sticker_as_leader).
--   * The old discord_rank_level permissions are gone. Buying the "Discord Rank" shop item set it to 1, and one
--     profiles policy treated level 1 as able to update ANYONE's profile (rename, and with the trigger's exception,
--     set gold). The legacy guild_bank / guild_donations tables and their two RPCs gated on it are Raid Leader only
--     now (the site uses guild_bank_snapshot; nothing calls these).
--   * Officers can no longer change anyone's gold through the API: protect_role_column refuses every direct gold
--     change. Gold moves only through the game's own functions (purchases, rewards, the Raid Leader's admin resets),
--     which run as trusted server code and skip this check.
-- Date: 2026-10-18
-- Reverse: re-run update_sticker_position and protect_role_column from the 2026-10-18 staging dump and recreate the
--          old policies listed below (not recommended).

-- ---------------------------------------------------------------- stickers
CREATE OR REPLACE FUNCTION public.update_sticker_position(p_sticker_id uuid, p_position_x numeric, p_position_y numeric)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_manager boolean;
BEGIN
  IF v_uid IS NULL THEN RETURN false; END IF;
  SELECT (p.role = 'officer' OR p.protected = true) INTO v_manager FROM public.profiles p WHERE p.id = v_uid;
  v_manager := COALESCE(v_manager, false);

  IF NOT v_manager THEN
    -- members: their own sticker only, and not on top of anyone else's
    IF NOT EXISTS (SELECT 1 FROM public.stickers s WHERE s.id = p_sticker_id AND s.placed_by_user_id = v_uid) THEN
      RETURN false;
    END IF;
    IF EXISTS (SELECT 1 FROM public.stickers o
               WHERE o.id <> p_sticker_id
                 AND sqrt(power(COALESCE(o.position_x, 50) - p_position_x, 2) + power(COALESCE(o.position_y, 50) - p_position_y, 2)) < 12) THEN
      RETURN false;
    END IF;
  END IF;

  UPDATE public.stickers SET position_x = p_position_x, position_y = p_position_y WHERE id = p_sticker_id;
  RETURN FOUND;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.update_sticker_position(uuid, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_sticker_position(uuid, numeric, numeric) TO authenticated;

-- ---------------------------------------------------------------- profiles: no discord-rank powers
DROP POLICY IF EXISTS "Officers and Raid Leaders can update anyone's profile" ON public.profiles;
CREATE POLICY "Officers and Raid Leaders can update anyone's profile" ON public.profiles
  FOR UPDATE USING (public.is_officer()) WITH CHECK (public.is_officer());

-- ---------------------------------------------------------------- gold: never changed by a direct API request
CREATE OR REPLACE FUNCTION public.protect_role_column()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
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

  -- Gold moves only through the game itself and the Raid Leader's admin tools (no officer or rank exception)
  if new.gold is distinct from old.gold or new.last_gold_claim_at is distinct from old.last_gold_claim_at then
    raise exception 'Gold can only be changed by the game or the Raid Leader''s admin tools';
  end if;

  if new.food is distinct from old.food
     or new.wood is distinct from old.wood
     or new.food_earned_total is distinct from old.food_earned_total
     or new.food_spent_total is distinct from old.food_spent_total
     or new.wood_earned_total is distinct from old.wood_earned_total
     or new.crystals is distinct from old.crystals
     or new.crystals_earned_total is distinct from old.crystals_earned_total
     or new.crystals_spent_total is distinct from old.crystals_spent_total
     or new.wood_spent_total is distinct from old.wood_spent_total
     or new.gold_earned_total is distinct from old.gold_earned_total
     or new.gold_spent_total is distinct from old.gold_spent_total
     or new.discord_rank_level is distinct from old.discord_rank_level then
    raise exception 'Resources, totals and rank can only be changed by the game itself';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------- legacy guild bank tables: Raid Leader only
DROP POLICY IF EXISTS "Officers can read guild bank" ON public.guild_bank;
DROP POLICY IF EXISTS "Officers can sync guild bank" ON public.guild_bank;
DROP POLICY IF EXISTS "Officers can read guild bank items" ON public.guild_bank_items;
DROP POLICY IF EXISTS "Officers can upload donations" ON public.guild_donations;
CREATE POLICY "Raid Leader manages legacy guild bank" ON public.guild_bank
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected));
CREATE POLICY "Raid Leader reads legacy guild bank items" ON public.guild_bank_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected));
CREATE POLICY "Raid Leader uploads legacy donations" ON public.guild_donations FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected));
-- their two RPCs checked discord_rank_level; nothing calls them, so nobody can
DO $$
BEGIN
  IF to_regprocedure('public.process_guild_bank_sync(integer, jsonb)') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public.process_guild_bank_sync(integer, jsonb) FROM PUBLIC, anon, authenticated;
  END IF;
  IF to_regprocedure('public.upload_guild_donations(integer, jsonb)') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public.upload_guild_donations(integer, jsonb) FROM PUBLIC, anon, authenticated;
  END IF;
END $$;
