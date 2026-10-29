# Feature: Couple games

Games the partners play together, live or at their own pace. All four games are playable: Tic-Tac-Toe, Would you rather, How well do you know me? and Conversation cards, built on one session model.

## Screen: Games hub (/games)
Opened from the Home "Games" pill and the Activity tab → Couple games. Lists every game with its status: start a game, your turn, or waiting for your partner. 

## Screen: Tic-Tac-Toe (/games/tic-tac-toe)
Start a game, tap a cell on your turn. The starter is X. The board updates live on both phones; if the partner is away, the game waits for them and they get one "your turn" push. Either partner can end the game; a finished game shows its result and "Play again".

## Screen: Would you rather (/games/would-you-rather)
Starting a game deals 10 questions from the bank (`lib/core/constants/game_content.dart`, append-only: a game stores indexes). Each partner answers A or B at their own pace. Your partner's pick for a question is shown only once you have answered it; matches are counted. The game finishes by itself when both have answered everything (or either ends it). The partner is told once, when you answer your last question.

## Screen: How well do you know me? (/games/quiz)
Starting a game deals 8 topics (`quizQuestions`, append-only, 4 options each). Per topic you pick your own answer, then guess your partner's; both are sent together as one sealed row `{self, guess}`. That keeps the server rule simple: the partner's row for a round is only returned once you have submitted the same round, so you can never see their answer before you have guessed. Scores: how many of their answers you guessed and how many of yours they guessed (`QuizScoring`). Finishes by itself when both are through all rounds; the partner is told once, on your last round.

## Screen: Conversation cards (/games/cards)
A shared deck of 15 cards (talk, truth or dare, from `conversationCards`, append-only) dealt when the game starts. Both phones show the same card; either partner taps "Next card" (the last one says "Finish"). The position is stored in the session state and changed with `update_game_state`, which needs no turn but does name the version, so two taps at once cannot both win (the loser sees the real card and a short message). No answers are stored and there is no push per card; the partner is told once when the game starts.

## Behaviour
- One running game per kind per couple. Both pressing "Start" lands in the same game (`start_game` returns the running one).
- A move names the version it was made on; a stale or out-of-turn move is rejected and the screen shows the real state.
- Starting a game counts toward the day streak. The partner gets a push (`NotifType.game`, own "Games" alert-sound group) when a game starts (not when they join one already running), when it finishes, and for Tic-Tac-Toe when it becomes their turn *and they are not looking at the board*. Looking at the board is announced on the couple channel's Presence as screen `game_tic_tac_toe` (like Touch and Canvas); it is withdrawn when the screen closes or the app goes to the background. Before the first Presence sync the app cannot tell, and sends the push. The decision runs after the move is saved, so it never slows a move down.
- Needs a connection to move; nothing is queued offline.

## Data
- Migrations: `supabase/migrations/couple_games.sql` (apply after `e2ee_content_text.sql`), then `couple_games_hardening.sql`.
- `game_sessions`: public state of a game, turn, version. Clients can only select (RLS `is_couple_member`); all writes go through `start_game`, `make_move`, `update_game_state` (a shared change with no turn), `finish_game`.
- `game_answers`: sealed (`enc`) per-round answers for the later quiz games; own rows readable, the partner's only through `get_game_answers` once you answered that round. Written by `submit_game_answer`. Used by Would you rather and the quiz: each answer is sealed with the couple key, bound to game, author and round. Answering needs the couple key (Profile → Security).
- The server enforces turn order and versions, not the game rules (the two partners trust each other).
- Answers (`submit_game_answer`) are accepted only for the quiz and Would you rather, strictly in order (round = how many you have answered) and inside the deck, up to 1000 rounds. This stops a player unlocking the partner's answer for a round they have not reached; resending a round already sent is a no-op. `update_game_state` works for Conversation cards only. Reading a game needs an active couple.
- Disconnect and account deletion remove the games (`disconnect_couple`, `delete_my_account` re-created).

## Code
- `lib/domain/games/tic_tac_toe.dart` (rules), `lib/domain/entities/game_session.dart`, `IGameRepository`
- `lib/data/repositories/game_repository.dart`, `lib/data/models/game_session_model.dart`
- `lib/presentation/features/games/` (`GamesBloc`, `TicTacToeBloc`, hub and game screens)
- `lib/presentation/features/games/bloc/would_you_rather_bloc.dart`, `screens/would_you_rather_screen.dart`, `GameAnswer`, `GameRepository.submitAnswer/getAnswers`
- `lib/presentation/features/games/bloc/quiz_bloc.dart`, `screens/quiz_screen.dart`, `lib/domain/games/quiz_scoring.dart`
- `lib/presentation/features/games/bloc/cards_bloc.dart`, `screens/cards_screen.dart`
- Tests: `test/domain/tic_tac_toe_test.dart`, `test/presentation/tic_tac_toe_bloc_test.dart`, `test/presentation/would_you_rather_bloc_test.dart`, `test/presentation/quiz_bloc_test.dart`, `test/presentation/cards_bloc_test.dart`, `test/domain/quiz_scoring_test.dart`
