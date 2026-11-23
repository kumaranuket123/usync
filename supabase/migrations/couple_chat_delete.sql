-- Private chat: either partner can delete any message of their couple's chat, for both of them.
-- Direct deletes stay refused (no delete policy); this function is the only way. Deleting the row
-- fires the existing AFTER DELETE trigger, which queues the sealed photo / voice file for removal
-- from Storage by the purge-chat Edge Function. Apply after couple_chat_timer.sql.
create or replace function public.delete_chat_message(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select couple_id into cid from public.chat_messages where id = p_id;
  -- Already gone (the partner deleted it too, or it expired): nothing to do.
  if cid is null then return; end if;
  if not public.is_active_couple_member(cid) then raise exception 'Not a member'; end if;
  delete from public.chat_messages where id = p_id;
end $$;

revoke all on function public.delete_chat_message(uuid) from public, anon;
grant execute on function public.delete_chat_message(uuid) to authenticated;
