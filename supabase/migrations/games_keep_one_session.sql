-- Keep only the latest finished game per couple: starting a new game clears the couple's older finished
-- sessions (their game_answers go with them through the cascade). A game still running is never touched.
-- Based on the live start_game; apply after couple_games_hardening.sql.

create or replace function public.start_game(p_id uuid, p_couple uuid, p_type text, p_state jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare existing uuid;
begin
  if not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;

  select id into existing from public.game_sessions
   where couple_id = p_couple and game_type = p_type and status = 'active';
  if existing is not null then return existing; end if;

  -- A new game: the finished ones before it are no longer needed.
  delete from public.game_sessions where couple_id = p_couple and status = 'finished';

  begin
    insert into public.game_sessions (id, couple_id, game_type, state, turn_user_id, created_by)
    values (p_id, p_couple, p_type, coalesce(p_state, '{}'::jsonb),
            case when p_type = 'tic_tac_toe' then auth.uid() end, auth.uid());
  exception when unique_violation then
    select id into existing from public.game_sessions
     where couple_id = p_couple and game_type = p_type and status = 'active';
    if existing is null then raise exception 'Could not start the game'; end if;
    return existing;
  end;
  return p_id;
end $$;

-- One-off: today's backlog. Keep each couple's most recent session, delete the older finished ones.
delete from public.game_sessions s
 where s.status = 'finished'
   and exists (select 1 from public.game_sessions n
                where n.couple_id = s.couple_id and n.created_at > s.created_at);
