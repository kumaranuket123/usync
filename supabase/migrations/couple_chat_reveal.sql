-- Photos and voice notes: the timer starts when the receiver REVEALS them (opens the photo, plays the
-- voice note), not when the message merely appears on their screen. The app now calls mark_chat_seen
-- for a photo or voice note only at that moment (text is still marked when it is on screen).
-- Until then it stays: an unrevealed photo or voice note lives 7 days (text still 1 day), as a safety
-- limit so unopened files do not pile up in Storage. Apply after couple_chat_shared_timer.sql.

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

  insert into public.chat_messages (id, couple_id, sender_id, kind, enc, media_path, ttl_seconds, expires_at)
  values (p_id, p_couple, auth.uid(), p_kind, p_enc, p_media_path, coalesce(ttl, 86400),
          now() + case when p_kind = 'text' then interval '1 day' else interval '7 days' end)
  on conflict (id) do nothing;

  if not exists (select 1 from public.chat_messages
                  where id = p_id and couple_id = p_couple and sender_id = auth.uid()) then
    raise exception 'Invalid message';
  end if;
  return p_id;
end $$;
