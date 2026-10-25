-- Usync — Supabase schema draft (Postgres + RLS).
-- Applied to Supabase project `usync` (omatuaemysgykmdgsqvr) as migration `initial_usync_schema`.
-- Replaces: firestore.rules (Firestore data) and the durable parts of RTDB.
-- Ephemeral state (presence, touch, live strokes) uses Realtime channels — see
-- the "Realtime authorization" section at the bottom.

create extension if not exists pgcrypto;

-- ───────────────────────── Enums ─────────────────────────
create type mood_type      as enum ('happy','thinkingAboutYou','missingYou','sleeping','relaxing','busy');
create type memory_type    as enum ('canvas','touch','mood','milestone');
create type notif_type     as enum ('touch','doodle','moodChange','streak','milestone');
-- Mirrors MilestoneType minus the synthetic `today` value (never stored).
create type milestone_type as enum ('firstConnect','firstDoodle','streak7','streak30','streak100','moments100','custom');

-- ───────────────────────── Tables ─────────────────────────
-- One row per auth user. Replaces Firestore `users/{uid}`.
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text not null,
  email        text not null,
  avatar_emoji text not null default '🦋',
  couple_id    uuid,                       -- FK added after couples exists
  created_at   timestamptz not null default now()
);

-- FCM tokens live apart from profiles so a partner can never read them.
-- Only the owner writes; the push Edge Function reads via the service role.
create table public.device_tokens (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  fcm_token  text not null,
  updated_at timestamptz not null default now()
);

-- Replaces Firestore `couples/{id}`. Rows are never deleted on disconnect so
-- memories/timeline history is kept.
create table public.couples (
  id                       uuid primary key default gen_random_uuid(),
  user_a_id                uuid not null references auth.users (id),
  user_b_id                uuid not null references auth.users (id),
  paired_at                timestamptz not null default now(),
  streak_days              int  not null default 0,
  total_moments            int  not null default 0,
  disconnect_requested_by  uuid references auth.users (id),
  disconnected_at          timestamptz,
  check (user_a_id <> user_b_id)
);

alter table public.profiles
  add constraint profiles_couple_fk foreign key (couple_id) references public.couples (id) on delete set null;

create index on public.couples (user_a_id);
create index on public.couples (user_b_id);
create index on public.profiles (couple_id);

-- Replaces Firestore `inviteCodes/{code}`.
create table public.invite_codes (
  code       text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  expires_at timestamptz not null
);
create index on public.invite_codes (user_id);

-- Replaces `moods/{coupleId}/history`. The "current" mood is the latest row.
create table public.moods (
  id         uuid primary key default gen_random_uuid(),
  couple_id  uuid not null references public.couples (id) on delete cascade,
  user_id    uuid not null references auth.users (id),
  type       mood_type not null,
  sent_at    timestamptz not null default now()
);
create index on public.moods (couple_id, sent_at desc);
create index on public.moods (user_id, sent_at desc);

-- Replaces `memories/{coupleId}/items`.
create table public.memories (
  id                 uuid primary key default gen_random_uuid(),
  couple_id          uuid not null references public.couples (id) on delete cascade,
  type               memory_type not null,
  thumbnail_emoji    text not null,
  title              text not null,
  created_by_user_id uuid not null references auth.users (id),
  thumbnail_url      text,
  is_favourited      boolean not null default false,
  created_at         timestamptz not null default now()
);
create index on public.memories (couple_id, created_at desc);
create index on public.memories (created_by_user_id);

-- Replaces `milestones/{coupleId}/events`.
create table public.milestones (
  id               uuid primary key default gen_random_uuid(),
  couple_id        uuid not null references public.couples (id) on delete cascade,
  type             milestone_type not null,
  title            text not null,
  occurred_at      timestamptz not null,
  note             text,
  linked_memory_id uuid references public.memories (id) on delete set null
);
create index on public.milestones (couple_id, occurred_at desc);
create index on public.milestones (linked_memory_id);

-- Replaces `notifications/{coupleId}/items`. Inserting a row triggers the push
-- Edge Function (database webhook); the recipient is the sender's partner.
create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  couple_id    uuid not null references public.couples (id) on delete cascade,
  from_user_id uuid not null references auth.users (id),
  type         notif_type not null,
  body_text    text not null,
  is_read      boolean not null default false,
  created_at   timestamptz not null default now()
);
create index on public.notifications (couple_id, created_at desc);
create index on public.notifications (from_user_id);

-- Replaces RTDB `canvas/{coupleId}/strokes`. Live chunks go over Realtime
-- Broadcast; the finished stroke is persisted here for late joiners.
create table public.canvas_strokes (
  id          uuid primary key,             -- generated by the client
  couple_id   uuid not null references public.couples (id) on delete cascade,
  user_id     uuid not null references auth.users (id),
  color       bigint  not null,             -- ARGB int
  width       real    not null,
  is_eraser   boolean not null default false,
  points      jsonb   not null,             -- flat [x0,y0,x1,y1,...]
  created_at  timestamptz not null default now()
);
create index on public.canvas_strokes (couple_id, created_at);
create index on public.canvas_strokes (user_id);

-- ───────────────────────── Helpers ─────────────────────────
-- SECURITY DEFINER so policies can check membership without recursive RLS.
create or replace function public.is_couple_member(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.couples c
    where c.id = cid and (select auth.uid()) in (c.user_a_id, c.user_b_id)
  );
$$;

-- Active = member of a couple that has not been disconnected.
create or replace function public.is_active_couple_member(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.couples c
    where c.id = cid and c.disconnected_at is null
      and (select auth.uid()) in (c.user_a_id, c.user_b_id)
  );
$$;

-- Create a profile when a user signs up. The app passes username/avatar in
-- signUp(data: {...}) which lands in raw_user_meta_data.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, email, avatar_emoji)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1)),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'avatar_emoji', '🦋')
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────── Pairing & disconnect RPCs ─────────────────────────
-- All couple-state changes go through these functions; clients get no direct
-- write access to `couples` or `profiles.couple_id`.

create or replace function public.join_with_code(p_code text)
returns public.couples language plpgsql security definer set search_path = public as $$
declare
  inv public.invite_codes;
  new_couple public.couples;
begin
  select * into inv from public.invite_codes where code = upper(p_code) for update;
  if not found then raise exception 'Invalid invite code'; end if;
  if inv.expires_at < now() then raise exception 'Invite code expired'; end if;
  if inv.user_id = auth.uid() then raise exception 'Cannot pair with yourself'; end if;
  if exists (select 1 from public.profiles where id in (inv.user_id, auth.uid()) and couple_id is not null) then
    raise exception 'One of you is already paired';
  end if;

  insert into public.couples (user_a_id, user_b_id) values (inv.user_id, auth.uid())
  returning * into new_couple;

  update public.profiles set couple_id = new_couple.id where id in (inv.user_id, auth.uid());
  delete from public.invite_codes where code = inv.code;
  return new_couple;
end $$;

create or replace function public.request_disconnect(p_couple uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active_couple_member(p_couple) then raise exception 'Not an active member'; end if;
  update public.couples set disconnect_requested_by = auth.uid() where id = p_couple;
end $$;

-- Withdraws your own request or declines your partner's.
create or replace function public.cancel_disconnect(p_couple uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active_couple_member(p_couple) then raise exception 'Not an active member'; end if;
  update public.couples set disconnect_requested_by = null where id = p_couple;
end $$;

-- Mutual confirmation: only the partner who did NOT request may confirm.
create or replace function public.confirm_disconnect(p_couple uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.couples;
begin
  select * into c from public.couples where id = p_couple for update;
  if not found or auth.uid() not in (c.user_a_id, c.user_b_id) then raise exception 'Not a member'; end if;
  if c.disconnected_at is not null then return; end if;
  if c.disconnect_requested_by is null or c.disconnect_requested_by = auth.uid() then
    raise exception 'No disconnect request from your partner to confirm';
  end if;

  update public.couples set disconnected_at = now() where id = p_couple;
  update public.profiles set couple_id = null where couple_id = p_couple;
end $$;

revoke all on function public.join_with_code(text), public.request_disconnect(uuid),
  public.cancel_disconnect(uuid), public.confirm_disconnect(uuid) from public, anon;
grant execute on function public.join_with_code(text), public.request_disconnect(uuid),
  public.cancel_disconnect(uuid), public.confirm_disconnect(uuid) to authenticated;

-- Helpers/trigger functions are not meant to be called over the API.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.is_couple_member(uuid), public.is_active_couple_member(uuid) from public, anon;
grant execute on function public.is_couple_member(uuid), public.is_active_couple_member(uuid) to authenticated;

-- ───────────────────────── Row Level Security ─────────────────────────
alter table public.profiles       enable row level security;
alter table public.device_tokens  enable row level security;
alter table public.couples        enable row level security;
alter table public.invite_codes   enable row level security;
alter table public.moods          enable row level security;
alter table public.memories       enable row level security;
alter table public.milestones     enable row level security;
alter table public.notifications  enable row level security;
alter table public.canvas_strokes enable row level security;

-- profiles: see yourself and your current partner (tighter than Firestore,
-- where any signed-in user could read every profile).
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (couple_id is not null and public.is_couple_member(couple_id)));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
-- Only these columns are client-editable; couple_id changes only via the RPCs.
revoke update on public.profiles from authenticated;
grant  update (username, avatar_emoji) on public.profiles to authenticated;

create policy device_tokens_own on public.device_tokens for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- couples: members read; all writes go through the RPCs above.
create policy couples_select on public.couples for select to authenticated
  using (public.is_couple_member(id));

-- invite codes: you manage only your own; joining uses join_with_code().
create policy invite_codes_insert on public.invite_codes for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy invite_codes_select_own on public.invite_codes for select to authenticated
  using (user_id = (select auth.uid()));
create policy invite_codes_delete_own on public.invite_codes for delete to authenticated
  using (user_id = (select auth.uid()));

-- moods
create policy moods_select on public.moods for select to authenticated
  using (public.is_couple_member(couple_id));
create policy moods_insert on public.moods for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_active_couple_member(couple_id));

-- memories
create policy memories_select on public.memories for select to authenticated
  using (public.is_couple_member(couple_id));
create policy memories_insert on public.memories for insert to authenticated
  with check (created_by_user_id = (select auth.uid()) and public.is_active_couple_member(couple_id));
create policy memories_update on public.memories for update to authenticated
  using (public.is_active_couple_member(couple_id)) with check (public.is_active_couple_member(couple_id));
create policy memories_delete on public.memories for delete to authenticated
  using (public.is_active_couple_member(couple_id));

-- milestones
create policy milestones_select on public.milestones for select to authenticated
  using (public.is_couple_member(couple_id));
create policy milestones_write on public.milestones for all to authenticated
  using (public.is_active_couple_member(couple_id)) with check (public.is_active_couple_member(couple_id));

-- notifications: can only be created as yourself, only inside your couple.
create policy notifications_select on public.notifications for select to authenticated
  using (public.is_couple_member(couple_id));
create policy notifications_insert on public.notifications for insert to authenticated
  with check (from_user_id = (select auth.uid()) and public.is_active_couple_member(couple_id));
create policy notifications_update on public.notifications for update to authenticated
  using (public.is_couple_member(couple_id)) with check (public.is_couple_member(couple_id));

-- canvas
create policy canvas_strokes_select on public.canvas_strokes for select to authenticated
  using (public.is_active_couple_member(couple_id));
create policy canvas_strokes_insert on public.canvas_strokes for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_active_couple_member(couple_id));
create policy canvas_strokes_delete on public.canvas_strokes for delete to authenticated
  using (public.is_active_couple_member(couple_id));

-- ───────────────────────── Realtime (Postgres changes) ─────────────────────────
-- Tables the app subscribes to (replaces Firestore snapshots()).
alter publication supabase_realtime add table public.couples, public.moods,
  public.memories, public.notifications, public.canvas_strokes;

-- ───────────────────────── Realtime authorization (Broadcast/Presence) ─────────────────────────
-- Private channels named 'couple:<couple_id>' carry presence, touch and live
-- stroke chunks. Replaces RTDB `members/` + database.rules.json.
-- Clients must connect with `private: true`.
create policy couple_channel_read on realtime.messages for select to authenticated
  using (
    realtime.topic() like 'couple:%'
    and public.is_active_couple_member(substr(realtime.topic(), 8)::uuid)
  );
create policy couple_channel_write on realtime.messages for insert to authenticated
  with check (
    realtime.topic() like 'couple:%'
    and public.is_active_couple_member(substr(realtime.topic(), 8)::uuid)
  );

-- ───────────────────────── Storage ─────────────────────────
-- Private bucket for memory bitmaps; object path = '<couple_id>/<file>'.
insert into storage.buckets (id, name, public) values ('memories', 'memories', false)
  on conflict do nothing;
create policy memories_objects_rw on storage.objects for all to authenticated
  using (bucket_id = 'memories' and public.is_active_couple_member(((storage.foldername(name))[1])::uuid))
  with check (bucket_id = 'memories' and public.is_active_couple_member(((storage.foldername(name))[1])::uuid));
