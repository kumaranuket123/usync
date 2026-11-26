-- Notifications as a mailbox (like chat_mailbox.sql): the list lives on the recipient's phone. The row
-- is only needed so the notify_push trigger can send the push; once the recipient's phone has saved it
-- it calls ack_notifications, which deletes the row. Read state is kept on the phone.
--
-- Apply before (or together with) the app build that calls it. Older builds still read the rows from the
-- server and keep working, they just see fewer of them.

create or replace function public.ack_notifications(p_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if cardinality(p_ids) > 1000 then raise exception 'Too many'; end if;
  -- Only the recipient (the sender's partner) collects.
  delete from public.notifications n
   where n.id = any (p_ids)
     and n.from_user_id is distinct from auth.uid()
     and public.is_couple_member(n.couple_id);
end $$;

revoke all on function public.ack_notifications(uuid[]) from public, anon;
grant execute on function public.ack_notifications(uuid[]) to authenticated;

-- A partner who never opens the app must not leave rows on the server for good: whenever a notification
-- is added, that couple's rows older than 14 days are deleted (uses the couple_id, created_at index).
create or replace function public.purge_old_notifications_for_couple()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.notifications
   where couple_id = new.couple_id and created_at < now() - interval '14 days';
  return null;
end $$;
revoke all on function public.purge_old_notifications_for_couple() from public, anon, authenticated;

drop trigger if exists notifications_purge_old on public.notifications;
create trigger notifications_purge_old after insert on public.notifications
  for each row execute function public.purge_old_notifications_for_couple();
