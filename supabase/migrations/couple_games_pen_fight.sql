-- Pen Fight game: a live game where the partners take turns flicking a pen across a desk. The
-- flicks travel as Broadcast events on the couple channel (nothing is stored per flick); the
-- session row only makes the game appear in the hub and tells the partner a game started.
-- Apply after couple_games_slap.sql.
-- No new table or RPC: start_game / finish_game are generic, and submit_game_answer /
-- update_game_state already refuse this game type.

alter table public.game_sessions drop constraint if exists game_sessions_game_type_check;
alter table public.game_sessions add constraint game_sessions_game_type_check
  check (game_type in ('tic_tac_toe', 'quiz', 'would_you_rather', 'cards', 'slap', 'pen_fight'));
