-- Either partner can end the couple on their own; no confirmation needed.
-- Replaces the request/cancel/confirm flow. The row is kept (history stays) and
-- both profiles lose their couple_id.
create or replace function public.disconnect_couple(p_couple uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.couples;
begin
  select * into c from public.couples where id = p_couple for update;
  if not found or auth.uid() not in (c.user_a_id, c.user_b_id) then raise exception 'Not a member'; end if;
  if c.disconnected_at is not null then return; end if;

  update public.couples
     set disconnected_at = now(), disconnect_requested_by = null
   where id = p_couple;
  update public.profiles set couple_id = null where couple_id = p_couple;
end $$;

revoke all on function public.disconnect_couple(uuid) from public, anon;
grant execute on function public.disconnect_couple(uuid) to authenticated;

drop function if exists public.request_disconnect(uuid);
drop function if exists public.cancel_disconnect(uuid);
drop function if exists public.confirm_disconnect(uuid);
