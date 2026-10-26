-- Security hardening from the app audit.
--
-- 1. rls_auto_enable() is an event-trigger helper (enables RLS on new public
--    tables). Event triggers run as the function owner, so it needs no API access.
revoke all on function public.rls_auto_enable() from public, anon, authenticated;

-- 2. Clients may only change the columns the app actually edits. Row-level
--    policies still decide WHICH rows; these grants decide which COLUMNS.

-- notifications: only the read flag (body_text, type, from_user_id are fixed at insert).
revoke update on public.notifications from authenticated;
grant  update (is_read) on public.notifications to authenticated;

-- memories: only the favourite flag (couple_id and created_by_user_id are fixed).
revoke update on public.memories from authenticated;
grant  update (is_favourited) on public.memories to authenticated;

-- milestones: editable content only (couple_id, created_by, last_notified_on and
-- linked_memory_id are not client-editable).
revoke update on public.milestones from authenticated;
grant  update (title, note, emoji, occurred_at, repeats_yearly) on public.milestones to authenticated;
