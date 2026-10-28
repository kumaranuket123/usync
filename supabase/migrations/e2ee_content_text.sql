-- End-to-end encryption, phase E2: text content.
--
-- New rows keep their content ONLY in an encrypted column; the old readable columns hold a harmless
-- placeholder. Old rows stay readable until each phone re-encrypts what it wrote (phase E5), so every
-- reader accepts both. The server never sees the couple key and cannot read any of these columns.
--
--  * moods.enc                   : mood type, custom label and emoji
--  * bucket_items.enc            : title, emoji, note
--  * question_answers.answer     : the answer, now ciphertext (so the 500-character limit is lifted)
--  * notifications.detail_enc    : the detail shown inside the app; body_text keeps a fixed sentence
--  * couples.next_meet_enc       : the next-meeting date (replaces next_meet_on)
--
-- Not in this phase: memories (with their pictures, phase E3) and timeline dates (with local
-- reminders, phase E4), because the server-side reminder job needs their readable dates.

alter table public.moods
  add column if not exists enc text check (enc is null or (enc like 'u1:%' and char_length(enc) <= 4096));
-- These tables grant INSERT per column, so the new column needs its own grant.
grant insert (enc) on public.moods to authenticated;

alter table public.bucket_items
  add column if not exists enc text check (enc is null or (enc like 'u1:%' and char_length(enc) <= 4096));
-- Clients may write the ciphertext when adding an item (the other content columns keep their grants).
grant insert (enc) on public.bucket_items to authenticated;

alter table public.notifications
  add column if not exists detail_enc text check (detail_enc is null or (detail_enc like 'u1:%' and char_length(detail_enc) <= 4096));
grant insert (detail_enc) on public.notifications to authenticated;

-- An encrypted answer is longer than the 500 characters it hides; the app still limits what people type.
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.question_answers'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) like '%char_length(answer)%' loop
    execute format('alter table public.question_answers drop constraint %I', c.conname);
  end loop;
end $$;
alter table public.question_answers drop constraint if exists question_answers_answer_len;
alter table public.question_answers add constraint question_answers_answer_len check (char_length(answer) between 1 and 4096);

-- ── The next meeting, encrypted ──────────────────────────────────────────────
alter table public.couples
  add column if not exists next_meet_enc text check (next_meet_enc is null or (next_meet_enc like 'u1:%' and char_length(next_meet_enc) <= 1024));

-- p_enc is the sealed date, or null to clear it. The readable date column is cleared when the sealed one is set.
create or replace function public.set_next_meet_enc(p_couple uuid, p_enc text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  if p_enc is not null and (char_length(p_enc) > 1024 or p_enc !~ '^u1:[A-Za-z0-9_=-]+$') then raise exception 'Invalid request'; end if;
  update public.couples set next_meet_enc = p_enc, next_meet_on = null where id = p_couple;
end $$;
revoke all on function public.set_next_meet_enc(uuid, text) from public, anon;
grant execute on function public.set_next_meet_enc(uuid, text) to authenticated;

-- Older builds still call set_next_meet: a date set that way replaces any sealed one, so the two
-- never disagree.
create or replace function public.set_next_meet(p_couple uuid, p_day date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  if p_day is not null and p_day < (now() at time zone 'utc')::date - 1 then
    raise exception 'Date is in the past';
  end if;
  update public.couples set next_meet_on = p_day, next_meet_enc = null where id = p_couple;
end $$;

-- ── Disconnect and delete clear the sealed date too ──────────────────────────
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
         streak_days = 0, streak_last_day = null, total_moments = 0,
         next_meet_on = null, next_meet_enc = null
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
           streak_days = 0, streak_last_day = null, total_moments = 0,
           next_meet_on = null, next_meet_enc = null
     where id = cid;
    update public.profiles set couple_id = null where couple_id = cid;
  end loop;

  delete from auth.users where id = uid;
end $$;
