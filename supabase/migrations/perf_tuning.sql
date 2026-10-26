-- Fixes found by the Supabase performance checks.

-- milestones had two permissive policies for SELECT (milestones_select and the
-- FOR ALL milestones_write), so every read evaluated both. Split the write
-- policy by command so reads use exactly one.
drop policy if exists milestones_write on public.milestones;
create policy milestones_insert on public.milestones for insert to authenticated
  with check (public.is_active_couple_member(couple_id));
create policy milestones_update on public.milestones for update to authenticated
  using (public.is_active_couple_member(couple_id))
  with check (public.is_active_couple_member(couple_id));
create policy milestones_delete on public.milestones for delete to authenticated
  using (public.is_active_couple_member(couple_id));

-- Foreign keys without a covering index slow down deletes and joins on the
-- referenced table (e.g. removing a user).
create index if not exists couple_activity_user_id_idx        on public.couple_activity (user_id);
create index if not exists couples_disconnect_requested_by_idx on public.couples (disconnect_requested_by);
create index if not exists milestones_created_by_idx           on public.milestones (created_by);
