-- Last known location per user, refreshed when they open the app. One row per
-- user; only the two members of an active couple can read it.
create table public.locations (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  couple_id  uuid not null references public.couples (id) on delete cascade,
  latitude   double precision not null,
  longitude  double precision not null,
  accuracy   real not null default 0,
  -- Partner may ask this device for a fresh fix while the app is closed.
  allow_background boolean not null default false,
  updated_at timestamptz not null default now()
);
create index on public.locations (couple_id);

alter table public.locations enable row level security;

create policy locations_select on public.locations for select to authenticated
  using (public.is_active_couple_member(couple_id));
create policy locations_insert_own on public.locations for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_active_couple_member(couple_id));
create policy locations_update_own on public.locations for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and public.is_active_couple_member(couple_id));
create policy locations_delete_own on public.locations for delete to authenticated
  using (user_id = (select auth.uid()));

-- 'location': "your partner is looking at your location".
-- 'locate':   partner asked for a fresh fix (visible push + silent wake-up, only
--             sent when the recipient set allow_background).
alter type public.notif_type add value if not exists 'location';
alter type public.notif_type add value if not exists 'locate';

-- Lets the app watch the partner's row so a requested fix appears live.
alter publication supabase_realtime add table public.locations;
