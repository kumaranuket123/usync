-- Hardening of couple_chat.sql after review. Apply after couple_chat.sql.
-- 1. Expired messages are no longer readable while they wait for the cron job.
-- 2. Clients can read, add and replace chat files but not delete them (the purge-chat function does,
--    with the service role), so a partner cannot remove the other's files early.
-- 3. The folder-to-uuid cast only runs for the chat bucket, so a non-uuid folder in another bucket
--    can never make this policy raise an error.

drop policy if exists chat_messages_select on public.chat_messages;
create policy chat_messages_select on public.chat_messages for select to authenticated
  using (expires_at > now() and public.is_active_couple_member(couple_id));

drop policy if exists chat_objects_rw     on storage.objects;
drop policy if exists chat_objects_select on storage.objects;
drop policy if exists chat_objects_insert on storage.objects;
drop policy if exists chat_objects_update on storage.objects;

create policy chat_objects_select on storage.objects for select to authenticated
  using (case when bucket_id = 'chat' then public.is_active_couple_member(((storage.foldername(name))[1])::uuid) else false end);
create policy chat_objects_insert on storage.objects for insert to authenticated
  with check (case when bucket_id = 'chat' then public.is_active_couple_member(((storage.foldername(name))[1])::uuid) else false end);
-- Replacing a file (a retried upload) needs update.
create policy chat_objects_update on storage.objects for update to authenticated
  using (case when bucket_id = 'chat' then public.is_active_couple_member(((storage.foldername(name))[1])::uuid) else false end)
  with check (case when bucket_id = 'chat' then public.is_active_couple_member(((storage.foldername(name))[1])::uuid) else false end);
