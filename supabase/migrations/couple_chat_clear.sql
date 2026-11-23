-- Private chat: either partner can clear the whole chat of their couple, for both of them.
-- Direct deletes stay refused; this function is the only way. The AFTER DELETE trigger queues
-- every sealed photo / voice file for removal by the purge-chat Edge Function.
-- Apply after couple_chat_delete.sql.
create or replace function public.clear_chat(p_couple uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  delete from public.chat_messages where couple_id = p_couple;
end $$;

revoke all on function public.clear_chat(uuid) from public, anon;
grant execute on function public.clear_chat(uuid) to authenticated;
