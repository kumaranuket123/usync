-- Shared bucket list / couple goals: things the couple wants to do together.
-- Either partner can add, edit, tick off and delete items. Ids are chosen by the
-- app (so an offline add can be retried safely). Who ticked an item and when is
-- only ever set by the RPC below, never by a client write.
--
-- Apply after next_meet.sql: it re-creates disconnect_couple / delete_my_account
-- on top of that version, and a later re-creation would drop the bucket_items delete.

create table if not exists public.bucket_items (
  id         uuid primary key,
  couple_id  uuid not null references public.couples (id) on delete cascade,
  title      text not null check (char_length(title) between 1 and 120),
  emoji      text not null default '✨',
  note       text check (note is null or char_length(note) <= 300),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  done_at    timestamptz,
  done_by    uuid references auth.users (id) on delete set null
);
create index if not exists bucket_items_couple_idx     on public.bucket_items (couple_id, created_at desc);
create index if not exists bucket_items_created_by_idx on public.bucket_items (created_by);
create index if not exists bucket_items_done_by_idx    on public.bucket_items (done_by);

alter table public.bucket_items enable row level security;

drop policy if exists bucket_items_select on public.bucket_items;
create policy bucket_items_select on public.bucket_items for select to authenticated
  using (public.is_couple_member(couple_id));

drop policy if exists bucket_items_insert on public.bucket_items;
create policy bucket_items_insert on public.bucket_items for insert to authenticated
  with check (created_by = (select auth.uid()) and public.is_active_couple_member(couple_id));

drop policy if exists bucket_items_update on public.bucket_items;
create policy bucket_items_update on public.bucket_items for update to authenticated
  using (public.is_active_couple_member(couple_id)) with check (public.is_active_couple_member(couple_id));

drop policy if exists bucket_items_delete on public.bucket_items;
create policy bucket_items_delete on public.bucket_items for delete to authenticated
  using (public.is_active_couple_member(couple_id));

-- Policies decide WHICH rows; these grants decide which COLUMNS. A new item starts
-- not done, and done_at / done_by change only through set_bucket_item_done.
revoke all on public.bucket_items from anon;
revoke insert, update on public.bucket_items from authenticated;
grant insert (id, couple_id, title, emoji, note, created_by) on public.bucket_items to authenticated;
grant update (title, emoji, note) on public.bucket_items to authenticated;

create or replace function public.set_bucket_item_done(p_item uuid, p_done boolean)
returns void language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select couple_id into cid from public.bucket_items where id = p_item;
  if cid is null or not public.is_active_couple_member(cid) then raise exception 'Not a member'; end if;
  update public.bucket_items
     -- Ticking an already ticked item keeps who ticked it first and when.
     set done_at = case when p_done then coalesce(done_at, now()) end,
         done_by = case when p_done then coalesce(done_by, auth.uid()) end
   where id = p_item;
end $$;

revoke all on function public.set_bucket_item_done(uuid, boolean) from public, anon;
grant execute on function public.set_bucket_item_done(uuid, boolean) to authenticated;

-- Adding an item counts as activity for the day streak.
drop trigger if exists bucket_items_activity on public.bucket_items;
create trigger bucket_items_activity after insert on public.bucket_items
  for each row execute function public.record_activity('created_by');

-- The partner's phone watches the list live. Full replica identity so a delete
-- event carries the whole old row, not just the id.
alter table public.bucket_items replica identity full;
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bucket_items') then
    alter publication supabase_realtime add table public.bucket_items;
  end if;
end $$;

-- Disconnecting or deleting an account removes the list with everything else shared.
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

    update public.couples
       set disconnected_at = coalesce(disconnected_at, now()), disconnect_requested_by = null,
           streak_days = 0, streak_last_day = null, total_moments = 0, next_meet_on = null
     where id = cid;
    update public.profiles set couple_id = null where couple_id = cid;
  end loop;

  delete from auth.users where id = uid;
end $$;
