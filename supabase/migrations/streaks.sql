-- Day streak and moment count for a couple.
--
-- A streak day is a UTC day on which BOTH partners did something: shared a mood,
-- drew on the canvas or saved a memory. The streak is the run of consecutive
-- such days ending on the latest one; the app shows it as 0 once that day is
-- more than one day old (see CoupleModel). total_moments is the memory count.

-- One row per user per UTC day they were active; filled by triggers below.
create table if not exists public.couple_activity (
  couple_id uuid not null references public.couples (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  day       date not null,
  primary key (couple_id, user_id, day)
);
alter table public.couple_activity enable row level security;
create policy couple_activity_select on public.couple_activity for select to authenticated
  using (public.is_couple_member(couple_id));

alter table public.couples add column if not exists streak_last_day date;

create or replace function public.refresh_couple_stats(cid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  a uuid; b uuid;
  last_day date;
  run_len  int;
begin
  select user_a_id, user_b_id into a, b from public.couples where id = cid;
  if not found then return; end if;

  with both_days as (
    select day from public.couple_activity
    where couple_id = cid and user_id in (a, b)
    group by day having count(distinct user_id) = 2
  ), ranked as (
    -- consecutive days share the same (day - row number)
    select day, day - (row_number() over (order by day))::int as grp from both_days
  ), latest as (
    select max(day) as day from both_days
  )
  select (select day from latest),
         count(*) filter (where grp = (select grp from ranked where day = (select day from latest)))
    into last_day, run_len
  from ranked;

  update public.couples
     set streak_days     = coalesce(run_len, 0),
         streak_last_day = last_day,
         total_moments   = (select count(*) from public.memories where couple_id = cid)
   where id = cid;
end;
$$;

-- Records that the row's author was active today; recounts only the first time
-- that user is active on a given day, so drawing (many rows) stays cheap.
create or replace function public.record_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  author   uuid := (to_jsonb(new) ->> tg_argv[0])::uuid;
  inserted int;
begin
  insert into public.couple_activity (couple_id, user_id, day)
  values (new.couple_id, author, (now() at time zone 'utc')::date)
  on conflict do nothing;
  get diagnostics inserted = row_count;
  if inserted > 0 then perform public.refresh_couple_stats(new.couple_id); end if;
  return new;
end;
$$;

-- Memories change the moment count every time, not just on a user's first activity.
create or replace function public.memories_changed()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.refresh_couple_stats(coalesce(new.couple_id, old.couple_id));
  return null;
end;
$$;

revoke all on function public.refresh_couple_stats(uuid) from public, anon, authenticated;
revoke all on function public.record_activity()          from public, anon, authenticated;
revoke all on function public.memories_changed()         from public, anon, authenticated;

create trigger moods_activity   after insert on public.moods
  for each row execute function public.record_activity('user_id');
create trigger strokes_activity after insert on public.canvas_strokes
  for each row execute function public.record_activity('user_id');
create trigger memories_activity after insert on public.memories
  for each row execute function public.record_activity('created_by_user_id');
create trigger memories_stats   after insert or delete on public.memories
  for each row execute function public.memories_changed();

-- Backfill from existing data, then compute every couple once.
insert into public.couple_activity (couple_id, user_id, day)
select couple_id, user_id, (sent_at at time zone 'utc')::date from public.moods
union
select couple_id, user_id, (created_at at time zone 'utc')::date from public.canvas_strokes
union
select couple_id, created_by_user_id, (created_at at time zone 'utc')::date from public.memories
on conflict do nothing;

select public.refresh_couple_stats(id) from public.couples;
