-- Migration: Only the Raid Leader can change shop items
-- Purpose: any officer could edit shop items (name, description, PRICE) - a Rare border was briefly 500 instead of 1200
--          on launch day and was bought at that price. Changing the catalog is now the Raid Leader's alone
--          (profiles.protected), enforced here; the site shows the Edit buttons only to the Raid Leader too.
--          Everyone can still read the catalog; purchases go through SECURITY DEFINER functions and are unaffected.
-- Date: 2026-10-21
-- Reverse: DROP POLICY shop_items_raid_leader_write ON public.shop_items;
--          CREATE POLICY shop_items_officer_write ON public.shop_items TO authenticated USING (public.is_officer()) WITH CHECK (public.is_officer());

DROP POLICY IF EXISTS "Officers manage shop items" ON public.shop_items;
DROP POLICY IF EXISTS shop_items_officer_write ON public.shop_items;
DROP POLICY IF EXISTS shop_items_raid_leader_write ON public.shop_items;

CREATE POLICY shop_items_raid_leader_write ON public.shop_items
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.protected));
