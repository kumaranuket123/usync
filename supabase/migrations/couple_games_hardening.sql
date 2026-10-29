-- Hardening of couple_games.sql after a security review. Apply after couple_games.sql.
--
-- 1. Answers must be sent in order and inside the deck. Before, any round number was
--    accepted, so a player could send a throwaway answer for a round they had not reached
--    and then read the partner's real answer for it (get_game_answers shows the partner's
--    row for every round the caller has a row for). Now a round can only be unlocked by
--    answering it in turn.
-- 2. Only the quiz and would-you-rather take answers.
-- 3. update_game_state (a shared change with no turn) is for conversation cards only, so it
--    cannot be used to rewrite a tic-tac-toe board out of turn.
-- 4. start_game never hands back an id that is not a running game of this couple.
-- 5. Reading sessions and answers needs an active couple, like every write already does.

-- A hard ceiling on rounds, whatever the deck says.
alter table public.game_answers drop constraint if exists game_answers_round_idx_max;
alter table public.game_answers add constraint game_answers_round_idx_max check (round_idx < 1000);

create or replace function public.submit_game_answer(p_session uuid, p_round int, p_enc text)
returns void language plpgsql security definer set search_path = public as $$
declare
  s        public.game_sessions;
  mine     int;
  deck_len int;
begin
  -- Locked so two answers from the same player cannot both pass the order check.
  select * into s from public.game_sessions where id = p_session for update;
  if not found or not public.is_active_couple_member(s.couple_id) then raise exception 'Not a member'; end if;
  if s.status <> 'active' then raise exception 'Game is over'; end if;
  if s.game_type not in ('quiz', 'would_you_rather') then raise exception 'This game takes no answers'; end if;

  -- Sending the same round again (a retry after a dropped connection) changes nothing.
  if exists (select 1 from public.game_answers
              where session_id = p_session and user_id = auth.uid() and round_idx = p_round) then
    return;
  end if;

  select count(*) into mine from public.game_answers
   where session_id = p_session and user_id = auth.uid();
  deck_len := case when jsonb_typeof(s.state -> 'deck') = 'array' then jsonb_array_length(s.state -> 'deck') else 0 end;
  if deck_len = 0 or p_round <> mine or p_round >= deck_len then raise exception 'Invalid round'; end if;

  insert into public.game_answers (session_id, couple_id, user_id, round_idx, enc)
  values (p_session, s.couple_id, auth.uid(), p_round, p_enc);

  update public.game_sessions set version = version + 1, updated_at = now() where id = p_session;
end $$;

create or replace function public.update_game_state(p_session uuid, p_state jsonb, p_version int)
returns int language plpgsql security definer set search_path = public as $$
declare s public.game_sessions;
begin
  select * into s from public.game_sessions where id = p_session for update;
  if not found or not public.is_active_couple_member(s.couple_id) then raise exception 'Not a member'; end if;
  if s.game_type <> 'cards' then raise exception 'Not allowed for this game'; end if;
  if s.status <> 'active' then raise exception 'Game is over'; end if;
  if s.version <> p_version then raise exception 'Out of date'; end if;

  update public.game_sessions
     set state = p_state, version = version + 1, updated_at = now()
   where id = p_session;
  return s.version + 1;
end $$;

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
    -- The partner started the same game at the same moment: join theirs.
    select id into existing from public.game_sessions
     where couple_id = p_couple and game_type = p_type and status = 'active';
    if existing is null then raise exception 'Could not start the game'; end if;
    return existing;
  end;
  return p_id;
end $$;

create or replace function public.get_game_answers(p_session uuid)
returns table (round_idx int, user_id uuid, enc text)
language plpgsql stable security definer set search_path = public as $$
declare
  me  uuid := auth.uid();
  cid uuid;
begin
  select couple_id into cid from public.game_sessions where id = p_session;
  if cid is null or not public.is_active_couple_member(cid) then raise exception 'Not a member'; end if;

  return query
    select a.round_idx, a.user_id, a.enc
      from public.game_answers a
     where a.session_id = p_session
       and (a.user_id = me
            or exists (select 1 from public.game_answers m
                        where m.session_id = a.session_id and m.user_id = me and m.round_idx = a.round_idx));
end $$;

drop policy if exists game_sessions_select on public.game_sessions;
create policy game_sessions_select on public.game_sessions for select to authenticated
  using (public.is_active_couple_member(couple_id));

-- create or replace keeps the existing grants, but say so explicitly.
revoke all on function public.submit_game_answer(uuid, int, text)    from public, anon;
revoke all on function public.update_game_state(uuid, jsonb, int)    from public, anon;
revoke all on function public.start_game(uuid, uuid, text, jsonb)    from public, anon;
revoke all on function public.get_game_answers(uuid)                 from public, anon;
grant execute on function public.submit_game_answer(uuid, int, text) to authenticated;
grant execute on function public.update_game_state(uuid, jsonb, int) to authenticated;
grant execute on function public.start_game(uuid, uuid, text, jsonb) to authenticated;
grant execute on function public.get_game_answers(uuid)              to authenticated;
