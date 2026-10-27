-- Sharing a location is an upsert (insert ... on conflict do update). Postgres checks
-- the EXISTING row against the select policy too. A user whose old row belongs to a
-- couple they have since left (or been disconnected from) failed that check, so every
-- later "Share my location" was rejected with 403. Letting people always read their own
-- row lets the upsert move it to their current couple.
create policy locations_select_own on public.locations for select to authenticated
  using (user_id = (select auth.uid()));

-- Clear rows left behind by couples that were disconnected before disconnecting
-- started to delete them.
delete from public.locations l
using public.couples c
where c.id = l.couple_id and c.disconnected_at is not null;
