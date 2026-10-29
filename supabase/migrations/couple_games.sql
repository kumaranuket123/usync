-- Couple games: one generic session table for every game (tic-tac-toe, quiz,
-- would you rather, conversation cards), plus per-round private answers.
--
-- A session holds the public board/state of one game. All writes go through the
-- RPCs below (clients have no insert/update/delete on either table), so the turn
-- order and the "answers stay hidden until you answered too" rule are enforced
-- on the server. Personal answers are sealed on the phone (`enc`); the server
-- only ever holds ciphertext for them.
--
-- Apply after e2ee_content_text.sql (the latest to re-create disconnect_couple /
-- delete_my_account): this file re-creates them on top of that version, and a later
-- re-creation would drop the game_sessions delete.

alter type public.notif_type add value if not exists 'game';

create table if not exists public.game_sessions (
  id           uuid primary key,
  couple_id    uuid not null references public.couples (id) on delete cascade,
  game_type    text not null check (game_type in ('tic_tac_toe', 'quiz', 'would_you_rather', 'cards')),
  status       text not null default 'active' check (status in ('active', 'finished')),
  state        jsonb not null default '{}'::jsonb check (pg_column_size(state) <= 16384),
  turn_user_id uuid references auth.users (id) on delete set null,
  created_by   uuid references auth.users (id) on delete set null,
  version      int  not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists game_sessions_couple_idx     on public.game_sessions (couple_id, updated_at desc);
create index if not exists game_sessions_created_by_idx on public.game_sessions (created_by);
create index if not exists game_sessions_turn_idx       on public.game_sessions (turn_user_id);
-- One running game of each kind per couple, so both pressing "start" lands in the same game.
create unique index if not exists game_sessions_one_active
  on public.game_sessions (couple_id, game_type) where status = 'active';

alter table public.game_sessions enable row level security;

drop policy if exists game_sessions_select on public.game_sessions;
create policy game_sessions_select on public.game_sessions for select to authenticated
  using (public.is_couple_member(couple_id));

revoke all on public.game_sessions from anon, authenticated;
grant select on public.game_sessions to authenticated;

create table if not exists public.game_answers (
  session_id uuid not null references public.game_sessions (id) on delete cascade,
  couple_id  uuid not null references public.couples (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  round_idx  int  not null check (round_idx >= 0),
  enc        text not null check (enc like 'u1:%' and char_length(enc) <= 4096),
  created_at timestamptz not null default now(),
  primary key (session_id, user_id, round_idx)
);
create index if not exists game_answers_couple_idx on public.game_answers (couple_id);
create index if not exists game_answers_user_idx   on public.game_answers (user_id);

alter table public.game_answers enable row level security;

-- Only your own rows are readable directly; the partner's come from get_game_answers.
drop policy if exists game_answers_select on public.game_answers;
create policy game_answers_select on public.game_answers for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.game_answers from anon, authenticated;
grant select on public.game_answers to authenticated;

-- Starts a game, or returns the one already running for this kind. The id is
-- chosen by the app so a retry cannot create a second game.
create or replace function public.start_game(p_id uuid, p_couple uuid, p_type text, p_state jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare existing uuid;
begin
  if not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;

  select id into existing from public.game_sessions
   where couple_id = p_couple and game_type = p_type and status = 'active';
  if existing is not null then return existing; end if;

  begin
    insert into public.game_sessions (id, couple_id, game_type, state, turn_user_id, created_by)
    -- Only tic-tac-toe is played in turns; the other games have everyone answer at their own pace.
    values (p_id, p_couple, p_type, coalesce(p_state, '{}'::jsonb),
            case when p_type = 'tic_tac_toe' then auth.uid() end, auth.uid());
  exception when unique_violation then
    -- Retry of the same start, or the partner started at the same moment.
    select id into existing from public.game_sessions
     where couple_id = p_couple and game_type = p_type and status = 'active';
    if existing is not null then return existing; end if;
    return p_id;
  end;
  return p_id;
end $$;

-- A turn: only the player whose turn it is, and only on the version they saw.
-- The turn passes to the partner, unless the move ends the game.
create or replace function public.make_move(p_session uuid, p_state jsonb, p_version int, p_finish boolean)
returns int language plpgsql security definer set search_path = public as $$
declare
  s public.game_sessions;
  c public.couples;
  other uuid;
begin
  select * into s from public.game_sessions where id = p_session for update;
  if not found or not public.is_active_couple_member(s.couple_id) then raise exception 'Not a member'; end if;
  if s.status <> 'active' then raise exception 'Game is over'; end if;
  if s.turn_user_id is distinct from auth.uid() then raise exception 'Not your turn'; end if;
  if s.version <> p_version then raise exception 'Out of date'; end if;

  select * into c from public.couples where id = s.couple_id;
  other := case when auth.uid() = c.user_a_id then c.user_b_id else c.user_a_id end;

  update public.game_sessions
     set state        = p_state,
         version      = version + 1,
         status       = case when p_finish then 'finished' else status end,
         turn_user_id = case when p_finish then null else other end,
         updated_at   = now()
   where id = p_session;
  return s.version + 1;
end $$;

-- A shared change either partner may make at any time (the next conversation card), no turn
-- needed. Like make_move it names the version it was made on, so two taps at once cannot both win.
create or replace function public.update_game_state(p_session uuid, p_state jsonb, p_version int)
returns int language plpgsql security definer set search_path = public as $$
declare s public.game_sessions;
begin
  select * into s from public.game_sessions where id = p_session for update;
  if not found or not public.is_active_couple_member(s.couple_id) then raise exception 'Not a member'; end if;
  if s.status <> 'active' then raise exception 'Game is over'; end if;
  if s.version <> p_version then raise exception 'Out of date'; end if;

  update public.game_sessions
     set state = p_state, version = version + 1, updated_at = now()
   where id = p_session;
  return s.version + 1;
end $$;

-- Either partner can end a game (finished or abandoned).
create or replace function public.finish_game(p_session uuid)
returns void language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select couple_id into cid from public.game_sessions where id = p_session;
  if cid is null or not public.is_active_couple_member(cid) then raise exception 'Not a member'; end if;
  update public.game_sessions
     set status = 'finished', turn_user_id = null, version = version + 1, updated_at = now()
   where id = p_session and status = 'active';
end $$;

-- A sealed answer for one round. Final once sent. Bumps the session so the
-- partner's phone, which watches the session, knows to look again.
create or replace function public.submit_game_answer(p_session uuid, p_round int, p_enc text)
returns void language plpgsql security definer set search_path = public as $$
declare s public.game_sessions;
begin
  select * into s from public.game_sessions where id = p_session;
  if not found or not public.is_active_couple_member(s.couple_id) then raise exception 'Not a member'; end if;
  if s.status <> 'active' then raise exception 'Game is over'; end if;

  insert into public.game_answers (session_id, couple_id, user_id, round_idx, enc)
  values (p_session, s.couple_id, auth.uid(), p_round, p_enc)
  on conflict do nothing;

  update public.game_sessions set version = version + 1, updated_at = now() where id = p_session;
end $$;

-- Your answers, and the partner's only for rounds you have answered yourself.
create or replace function public.get_game_answers(p_session uuid)
returns table (round_idx int, user_id uuid, enc text)
language plpgsql stable security definer set search_path = public as $$
declare
  me  uuid := auth.uid();
  cid uuid;
begin
  select couple_id into cid from public.game_sessions where id = p_session;
  if cid is null or not public.is_couple_member(cid) then raise exception 'Not a member'; end if;

  return query
    select a.round_idx, a.user_id, a.enc
      from public.game_answers a
     where a.session_id = p_session
       and (a.user_id = me
            or exists (select 1 from public.game_answers m
                        where m.session_id = a.session_id and m.user_id = me and m.round_idx = a.round_idx));
end $$;

revoke all on function public.start_game(uuid, uuid, text, jsonb)       from public, anon;
revoke all on function public.make_move(uuid, jsonb, int, boolean)      from public, anon;
revoke all on function public.update_game_state(uuid, jsonb, int)       from public, anon;
revoke all on function public.finish_game(uuid)                         from public, anon;
revoke all on function public.submit_game_answer(uuid, int, text)       from public, anon;
revoke all on function public.get_game_answers(uuid)                    from public, anon;
grant execute on function public.start_game(uuid, uuid, text, jsonb)    to authenticated;
grant execute on function public.make_move(uuid, jsonb, int, boolean)   to authenticated;
grant execute on function public.update_game_state(uuid, jsonb, int)    to authenticated;
grant execute on function public.finish_game(uuid)                      to authenticated;
grant execute on function public.submit_game_answer(uuid, int, text)    to authenticated;
grant execute on function public.get_game_answers(uuid)                 to authenticated;

-- Starting a game counts as activity for the day streak.
drop trigger if exists game_sessions_activity on public.game_sessions;
create trigger game_sessions_activity after insert on public.game_sessions
  for each row execute function public.record_activity('created_by');

-- The partner's phone watches the game live. Full replica identity so an update
-- event carries the whole row.
alter table public.game_sessions replica identity full;
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'game_sessions') then
    alter publication supabase_realtime add table public.game_sessions;
  end if;
end $$;

-- Disconnecting or deleting an account removes the games with everything else shared
-- (answers go with their session).
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
  delete from public.game_sessions    where couple_id = p_couple;
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
    delete from public.game_sessions    where couple_id = cid;
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
