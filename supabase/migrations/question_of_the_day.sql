-- Question of the day: each partner answers privately; the partner's answer is
-- only returned once the caller has answered too (enforced in the RPC; the
-- table itself only lets a user read their own rows).
--
-- The question text lives in the app (picked by day), so only the answer and
-- the question index are stored.

alter type public.notif_type add value if not exists 'question';

create table if not exists public.question_answers (
  couple_id    uuid not null references public.couples (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  day          date not null,
  question_idx int  not null check (question_idx >= 0),
  answer       text not null check (char_length(answer) between 1 and 500),
  created_at   timestamptz not null default now(),
  primary key (couple_id, user_id, day)
);
create index if not exists question_answers_user_idx on public.question_answers (user_id);

alter table public.question_answers enable row level security;

drop policy if exists question_answers_select on public.question_answers;
create policy question_answers_select on public.question_answers for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists question_answers_insert on public.question_answers;
create policy question_answers_insert on public.question_answers for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_active_couple_member(couple_id));

-- No update/delete policies: an answer is final once sent.

-- Today's state for the caller: their own answer, whether the partner has
-- answered, and the partner's answer only when the caller has answered.
create or replace function public.get_question_state(p_couple uuid, p_day date)
returns table (my_answer text, partner_answered boolean, partner_answer text)
language plpgsql stable security definer set search_path = public as $$
declare
  me   uuid := auth.uid();
  mine text;
begin
  if not public.is_couple_member(p_couple) then raise exception 'Not a member'; end if;

  select a.answer into mine from public.question_answers a
   where a.couple_id = p_couple and a.user_id = me and a.day = p_day;

  return query
    select mine,
           exists (select 1 from public.question_answers a
                    where a.couple_id = p_couple and a.user_id <> me and a.day = p_day),
           case when mine is null then null else
             (select a.answer from public.question_answers a
               where a.couple_id = p_couple and a.user_id <> me and a.day = p_day)
           end;
end $$;

revoke all on function public.get_question_state(uuid, date) from public, anon;
grant execute on function public.get_question_state(uuid, date) to authenticated;

-- An answer counts as activity for the day streak.
drop trigger if exists question_answers_activity on public.question_answers;
create trigger question_answers_activity after insert on public.question_answers
  for each row execute function public.record_activity('user_id');

-- Disconnecting deletes the couple's answers too (built on disconnect_deletes_data.sql).
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
         streak_days = 0, streak_last_day = null, total_moments = 0
   where id = p_couple;
  update public.profiles set couple_id = null where couple_id = p_couple;
end $$;

-- Deleting an account also removes the couple's answers (the partner's included),
-- since the couples row survives as a tombstone and the cascade never fires.
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
           streak_days = 0, streak_last_day = null, total_moments = 0
     where id = cid;
    update public.profiles set couple_id = null where couple_id = cid;
  end loop;

  delete from auth.users where id = uid;
end $$;
