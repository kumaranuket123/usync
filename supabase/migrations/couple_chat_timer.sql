-- Chat timer choice. Apply after couple_chat_hardening.sql.
-- Each message carries how long it lives after the receiver has seen it (chosen by its sender:
-- 10 seconds, 1 minute, 5 minutes, 1 hour or 1 day; the default is 1 day). A message nobody opens is
-- deleted after 1 day (it was 7 days).

alter table public.chat_messages
  add column if not exists ttl_seconds int not null default 86400;
alter table public.chat_messages drop constraint if exists chat_messages_ttl_allowed;
alter table public.chat_messages add constraint chat_messages_ttl_allowed
  check (ttl_seconds in (10, 60, 300, 3600, 86400));

alter table public.chat_messages alter column expires_at set default now() + interval '1 day';

-- The old five-argument version is replaced, so there is one function. An older app that does not
-- send the timer gets the 1-day default.
drop function if exists public.send_chat_message(uuid, uuid, text, text, text);
create or replace function public.send_chat_message(
  p_id uuid, p_couple uuid, p_kind text, p_enc text, p_media_path text, p_ttl int default 86400)
returns uuid language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  if p_kind not in ('text', 'image', 'voice') then raise exception 'Invalid kind'; end if;
  if p_ttl not in (10, 60, 300, 3600, 86400) then raise exception 'Invalid timer'; end if;
  if p_kind = 'text' then
    if p_media_path is not null then raise exception 'Invalid media'; end if;
  elsif p_media_path is distinct from (p_couple::text || '/' || p_id::text || '.enc') then
    raise exception 'Invalid media';
  end if;

  insert into public.chat_messages (id, couple_id, sender_id, kind, enc, media_path, ttl_seconds)
  values (p_id, p_couple, auth.uid(), p_kind, p_enc, p_media_path, p_ttl)
  on conflict (id) do nothing;

  if not exists (select 1 from public.chat_messages
                  where id = p_id and couple_id = p_couple and sender_id = auth.uid()) then
    raise exception 'Invalid message';
  end if;
  return p_id;
end $$;

-- The timer starts when the receiver sees the message and lasts what its sender chose.
create or replace function public.mark_chat_seen(p_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update public.chat_messages m
     set seen_at = now(), expires_at = now() + make_interval(secs => m.ttl_seconds)
   where m.id = any (p_ids)
     and m.seen_at is null
     and m.sender_id is distinct from auth.uid()
     and public.is_active_couple_member(m.couple_id);
end $$;

revoke all on function public.send_chat_message(uuid, uuid, text, text, text, int) from public, anon;
grant execute on function public.send_chat_message(uuid, uuid, text, text, text, int) to authenticated;
