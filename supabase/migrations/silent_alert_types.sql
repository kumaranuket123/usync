-- Recipient preference: which notification types arrive without sound or a
-- heads-up popup. Keys are the app's alert groups (touch, doodle, moodChange,
-- streak, milestone, location). Location alerts are quiet by default.
alter table public.device_tokens
  add column if not exists silent_types text[] not null default array['location'];
