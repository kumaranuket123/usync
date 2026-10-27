-- "Next time we meet": one shared date per couple, set by either partner (used by
-- the long-distance card on Home). Stored as a plain calendar date; the app
-- treats a date in the past as "not set". Like every couple state change it goes
-- through an RPC.
--
-- A past date is refused, with one day of slack so someone ahead of UTC can still
-- pick their own "today".

alter table public.couples add column if not exists next_meet_on date;

create or replace function public.set_next_meet(p_couple uuid, p_day date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  if p_day is not null and p_day < (now() at time zone 'utc')::date - 1 then
    raise exception 'Date is in the past';
  end if;
  update public.couples set next_meet_on = p_day where id = p_couple;
end $$;

revoke all on function public.set_next_meet(uuid, date) from public, anon;
grant execute on function public.set_next_meet(uuid, date) to authenticated;

-- Disconnecting or deleting an account clears the date with everything else shared.
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

    update public.couples
       set disconnected_at = coalesce(disconnected_at, now()), disconnect_requested_by = null,
           streak_days = 0, streak_last_day = null, total_moments = 0, next_meet_on = null
     where id = cid;
    update public.profiles set couple_id = null where couple_id = cid;
  end loop;

  delete from auth.users where id = uid;
end $$;
