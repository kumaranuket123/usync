# Feature: Question of the Day

One shared question per day. Each partner answers privately; the partner's answer is only shown once you have answered too. Works for long-distance and in-person couples alike.

---

## Screens

### QuestionScreen (`/question`)

Not a bottom-nav tab. Opened from the 💬 Question pill on HomeScreen, or by tapping a `question` notification.

**Layout:**
1. Header: `NeonBackButton`, "Question of the day", subtitle "Answers are shown once you both reply"
2. The question text
3. Before you answer: `GlassInput` (max 500 chars), a hint whether the partner has answered, and a `GlowButton` "Send answer"
4. After you answer: your answer card, then either the partner's answer card or "Waiting for your partner to answer…"

The screen re-checks every 20 seconds while open, so the partner's answer appears without leaving.

---

## Behaviour

- The question is picked from the couple's bank (`DailyQuestion.bankFor(mode)`: shared questions plus Together or Long-distance ones, see [relationship-mode](relationship-mode.md)) by UTC day (`DailyQuestion.forDay`), so both partners see the same one. The day matches the server's UTC streak day.
- An answer is final: there is no edit or delete.
- Answering needs a connection (it is not queued in the outbox, because the reveal depends on the server).
- Answering counts as activity for the day streak (`record_activity` trigger).
- The partner gets a `question` push ("<name> answered today's question 💬"); it has its own switch in Alert sounds.

---

## Data

Table `question_answers` (`couple_id`, `user_id`, `day`, `question_idx`, `answer`), primary key `(couple_id, user_id, day)`. RLS lets a user read only their own rows and insert their own row while in an active couple.

RPC `get_question_state(p_couple, p_day)` returns `my_answer`, `partner_answered` and `partner_answer`; the partner's text is `null` until the caller has answered. Migration: `supabase/migrations/question_of_the_day.sql`. `disconnect_couple` deletes the couple's answers.

## Code

`DailyQuestion` / `QuestionState` (`domain/entities/daily_question.dart`), `IQuestionRepository`, `QuestionRepository`, `QuestionBloc`, `QuestionScreen`.
