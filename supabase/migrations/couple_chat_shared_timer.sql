-- Chat timer is shared by the couple: whoever changes it changes it for both partners, and the
-- server applies it to every new message (from either of them). Apply after couple_chat_delete.sql.
-- Messages already sent keep the timer they were sent with.

alter table public.couples
  add column if not exists chat_ttl_seconds int not null default 86400;
alter table public.couples drop constraint if exists couples_chat_ttl_allowed;
alter table public.couples add constraint couples_chat_ttl_allowed
  check (chat_ttl_seconds in (10, 60, 300, 3600, 86400));

-- Either partner sets the couple's timer. The clients read the column and see changes through
-- the couples row stream (couples is already in the Realtime publication).
create or replace function public.set_chat_timer(p_couple uuid, p_seconds int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  if p_seconds not in (10, 60, 300, 3600, 86400) then raise exception 'Invalid timer'; end if;
  update public.couples set chat_ttl_seconds = p_seconds where id = p_couple;
end $$;
revoke all on function public.set_chat_timer(uuid, int) from public, anon;
grant execute on function public.set_chat_timer(uuid, int) to authenticated;

-- The message's timer is the couple's timer at the moment it reaches the server. p_ttl is still
-- accepted (and checked) so an older app keeps working, but it no longer decides anything.
create or replace function public.send_chat_message(
  p_id uuid, p_couple uuid, p_kind text, p_enc text, p_media_path text, p_ttl int default 86400)
returns uuid language plpgsql security definer set search_path = public as $$
declare ttl int;
begin
  if auth.uid() is null or not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  if p_kind not in ('text', 'image', 'voice') then raise exception 'Invalid kind'; end if;
  if p_ttl not in (10, 60, 300, 3600, 86400) then raise exception 'Invalid timer'; end if;
  if p_kind = 'text' then
    if p_media_path is not null then raise exception 'Invalid media'; end if;
  elsif p_media_path is distinct from (p_couple::text || '/' || p_id::text || '.enc') then
    raise exception 'Invalid media';
  end if;

  select chat_ttl_seconds into ttl from public.couples where id = p_couple;

  insert into public.chat_messages (id, couple_id, sender_id, kind, enc, media_path, ttl_seconds)
  values (p_id, p_couple, auth.uid(), p_kind, p_enc, p_media_path, coalesce(ttl, 86400))
  on conflict (id) do nothing;

  if not exists (select 1 from public.chat_messages
                  where id = p_id and couple_id = p_couple and sender_id = auth.uid()) then
    raise exception 'Invalid message';
  end if;
  return p_id;
end $$;
