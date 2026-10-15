-- news, comp_slots and shop_items had Row-Level Security turned off, and the "authenticated" role has
-- ALL on them, so any signed-in member could post or delete news, rewrite the raid comp, or change
-- shop prices straight from the browser. Turn RLS on: everyone can read, only officers
-- (is_officer(): role = 'officer', which includes the protected Raid Leader) can write.
-- service_role bypasses RLS, so server-side jobs are unaffected.

alter table public.news enable row level security;
alter table public.comp_slots enable row level security;
alter table public.shop_items enable row level security;

drop policy if exists news_read on public.news;
drop policy if exists news_officer_write on public.news;
create policy news_read on public.news for select to anon, authenticated using (true);
create policy news_officer_write on public.news for all to authenticated using (public.is_officer()) with check (public.is_officer());

drop policy if exists comp_slots_read on public.comp_slots;
drop policy if exists comp_slots_officer_write on public.comp_slots;
create policy comp_slots_read on public.comp_slots for select to anon, authenticated using (true);
create policy comp_slots_officer_write on public.comp_slots for all to authenticated using (public.is_officer()) with check (public.is_officer());

drop policy if exists shop_items_read on public.shop_items;
drop policy if exists shop_items_officer_write on public.shop_items;
create policy shop_items_read on public.shop_items for select to anon, authenticated using (true);
create policy shop_items_officer_write on public.shop_items for all to authenticated using (public.is_officer()) with check (public.is_officer());
