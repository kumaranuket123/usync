-- Custom moods: a user types their own label and picks an emoji ("Craving pizza 🍕").
-- Stored as type 'custom' with the text alongside; the built-in moods are unchanged.
alter type public.mood_type add value if not exists 'custom';

alter table public.moods
  add column if not exists custom_label text check (char_length(custom_label) <= 40),
  add column if not exists custom_emoji text check (char_length(custom_emoji) <= 16);
