-- Replaces chat_push_delivered.sql: marking a message delivered when FCM accepted the push was wrong for a
-- phone that was offline. The partner's phone now sends the delivered receipt itself (see send-push's
-- `chat_delivered` data push), so the column is not used.
alter table public.chat_messages drop column if exists delivered_at;
