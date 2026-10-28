-- End-to-end encryption, phase E1: the keys. No content is encrypted yet.
--
-- The server only ever holds public information and things it cannot open:
--  * user_public_keys : each person's X25519 PUBLIC key (readable by them and their partner).
--  * user_key_backups : the person's identity key sealed with their recovery phrase; only they
--    can read it, and without the phrase it cannot be opened.
--  * couple_keys      : the couple's key, sealed separately to each partner's public key; each
--    person can read only their own row.
-- Nothing here can reveal a private key or a couple key to the server.
--
-- Writes to public keys and couple keys go through functions that check membership; clients
-- cannot write those tables directly. The server can still refuse to serve or swap a public key
-- (a man-in-the-middle), which is why partners compare a security code in the app.

-- A partner is someone who shares my active couple.
create or replace function public.is_my_partner(other uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
      from public.profiles me
      join public.profiles p on p.couple_id = me.couple_id
     where me.id = (select auth.uid())
       and p.id = other
       and me.couple_id is not null
       and public.is_active_couple_member(me.couple_id));
$$;
revoke all on function public.is_my_partner(uuid) from public, anon;
grant execute on function public.is_my_partner(uuid) to authenticated;

-- ── Public keys ──────────────────────────────────────────────────────────────
create table if not exists public.user_public_keys (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  -- Canonical base64 of exactly 32 bytes (one spelling per key), and not the all-zero key.
  public_key text not null check (
    public_key ~ '^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$'
    and public_key <> 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='),
  updated_at timestamptz not null default now()
);
alter table public.user_public_keys enable row level security;

drop policy if exists user_public_keys_select on public.user_public_keys;
create policy user_public_keys_select on public.user_public_keys for select to authenticated
  using (user_id = (select auth.uid()) or public.is_my_partner(user_id));

revoke all on public.user_public_keys from anon, authenticated;
grant select on public.user_public_keys to authenticated;

create or replace function public.publish_public_key(p_key text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  insert into public.user_public_keys (user_id, public_key) values (auth.uid(), p_key)
  on conflict (user_id) do update set public_key = excluded.public_key, updated_at = now();
end $$;
revoke all on function public.publish_public_key(text) from public, anon;
grant execute on function public.publish_public_key(text) to authenticated;

-- ── Recovery backups ─────────────────────────────────────────────────────────
create table if not exists public.user_key_backups (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  backup     text not null check (char_length(backup) between 1 and 2048),
  updated_at timestamptz not null default now()
);
alter table public.user_key_backups enable row level security;

drop policy if exists user_key_backups_select on public.user_key_backups;
create policy user_key_backups_select on public.user_key_backups for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists user_key_backups_insert on public.user_key_backups;
create policy user_key_backups_insert on public.user_key_backups for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists user_key_backups_update on public.user_key_backups;
create policy user_key_backups_update on public.user_key_backups for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists user_key_backups_delete on public.user_key_backups;
create policy user_key_backups_delete on public.user_key_backups for delete to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.user_key_backups from anon, authenticated;
grant select, insert, update, delete on public.user_key_backups to authenticated;

-- ── Couple keys ──────────────────────────────────────────────────────────────
create table if not exists public.couple_keys (
  couple_id   uuid not null references public.couples (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  key_version int  not null check (key_version >= 1),
  wrapped_key text not null check (char_length(wrapped_key) between 1 and 512),
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  primary key (couple_id, user_id, key_version)
);
create index if not exists couple_keys_user_idx       on public.couple_keys (user_id);
create index if not exists couple_keys_created_by_idx on public.couple_keys (created_by);
alter table public.couple_keys enable row level security;

drop policy if exists couple_keys_select on public.couple_keys;
create policy couple_keys_select on public.couple_keys for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.couple_keys from anon, authenticated;
grant select on public.couple_keys to authenticated;

-- p_rows is a JSON object { "<user id>": "<wrapped key>" }.
--  * p_create = true : the first key for a NEW version (1 for the first, then max + 1). Both partners
--    must be covered. The first writer wins: if that version already exists (including a race) it
--    returns false and writes nothing.
--  * p_create = false: replace the OTHER partner's existing wrapped key (approving their new public
--    key). It only ever UPDATES an existing row: it cannot create a version, and nobody can replace
--    their own row.
-- A disconnected couple, a non-member and malformed input are all refused with a plain error.
create or replace function public.put_couple_keys(p_couple uuid, p_version int, p_rows jsonb, p_create boolean)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c        public.couples;
  me       uuid := auth.uid();
  r        record;
  uid      uuid;
  seen     uuid[] := '{}';
  newest   int;
  n        int := 0;
begin
  -- Lock the couple so a disconnect running at the same moment cannot leave keys behind.
  select * into c from public.couples where id = p_couple for share;
  if not found or c.disconnected_at is not null or me is null or me not in (c.user_a_id, c.user_b_id) then
    raise exception 'Not a member';
  end if;
  if p_version is null or p_version < 1 or p_rows is null or jsonb_typeof(p_rows) <> 'object' or p_create is null then
    raise exception 'Invalid request';
  end if;

  -- Check the whole request before writing anything.
  for r in select key, value from jsonb_each(p_rows) loop
    if r.key !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       or jsonb_typeof(r.value) <> 'string'
       or char_length(r.value #>> '{}') not between 1 and 512 then
      raise exception 'Invalid request';
    end if;
    uid := r.key::uuid;
    if uid = any (seen) then raise exception 'Invalid request'; end if;
    seen := seen || uid;
    if uid not in (c.user_a_id, c.user_b_id) then raise exception 'Not a member'; end if;
    if not p_create and uid = me then raise exception 'You cannot replace your own key'; end if;
    n := n + 1;
  end loop;
  if p_create and n <> 2 then raise exception 'A new key must be wrapped for both partners'; end if;
  if not p_create and n <> 1 then raise exception 'Replace one partner key at a time'; end if;

  if p_create then
    select coalesce(max(key_version), 0) into newest from public.couple_keys where couple_id = p_couple;
    if p_version <= newest then return false; end if;          -- someone got there first
    if p_version > newest + 1 then raise exception 'Invalid request'; end if;
    begin
      for r in select key, value #>> '{}' as wrapped from jsonb_each(p_rows) loop
        insert into public.couple_keys (couple_id, user_id, key_version, wrapped_key, created_by)
        values (p_couple, r.key::uuid, p_version, r.wrapped, me);
      end loop;
    exception when unique_violation then
      return false; -- someone else created it at the same moment
    end;
    return true;
  end if;

  for r in select key, value #>> '{}' as wrapped from jsonb_each(p_rows) loop
    update public.couple_keys
       set wrapped_key = r.wrapped, created_by = me, created_at = now()
     where couple_id = p_couple and user_id = r.key::uuid and key_version = p_version;
    if not found then raise exception 'There is no key to replace'; end if;
  end loop;
  return true;
end $$;
revoke all on function public.put_couple_keys(uuid, int, jsonb, boolean) from public, anon;
grant execute on function public.put_couple_keys(uuid, int, jsonb, boolean) to authenticated;

-- ── Disconnect and delete remove the couple's keys with everything else ─────
create or replace function public.disconnect_couple(p_couple uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.couples;
begin
  select * into c from public.couples where id = p_couple for update;
  if not found or auth.uid() not in (c.user_a_id, c.user_b_id) then raise exception 'Not a member'; end if;
  if c.disconnected_at is not null then return; end if;

  delete from public.moods            where couple_id = p_couple;
  delete from public.memories         where couple_id = p_couple;
  delete from public.milestones       where couple_id = p_couple;
  delete from public.notifications    where couple_id = p_couple;
  delete from public.canvas_strokes   where couple_id = p_couple;
  delete from public.locations        where couple_id = p_couple;
  delete from public.couple_activity  where couple_id = p_couple;
  delete from public.question_answers where couple_id = p_couple;
  delete from public.bucket_items     where couple_id = p_couple;
  delete from public.couple_keys      where couple_id = p_couple;

  update public.couples
     set disconnected_at = now(), disconnect_requested_by = null,
         streak_days = 0, streak_last_day = null, total_moments = 0, next_meet_on = null
   where id = p_couple;
  update public.profiles set couple_id = null where couple_id = p_couple;
end $$;

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  cid uuid;
begin
  if uid is null then raise exception 'Not signed in'; end if;

  for cid in select id from public.couples where uid in (user_a_id, user_b_id) loop
    delete from public.moods            where couple_id = cid;
    delete from public.memories         where couple_id = cid;
    delete from public.milestones       where couple_id = cid;
    delete from public.notifications    where couple_id = cid;
    delete from public.canvas_strokes   where couple_id = cid;
    delete from public.locations        where couple_id = cid;
    delete from public.couple_activity  where couple_id = cid;
    delete from public.question_answers where couple_id = cid;
    delete from public.bucket_items     where couple_id = cid;
    delete from public.couple_keys      where couple_id = cid;

    update public.couples
       set disconnected_at = coalesce(disconnected_at, now()), disconnect_requested_by = null,
           streak_days = 0, streak_last_day = null, total_moments = 0, next_meet_on = null
     where id = cid;
    update public.profiles set couple_id = null where couple_id = cid;
  end loop;

  delete from auth.users where id = uid;
end $$;
