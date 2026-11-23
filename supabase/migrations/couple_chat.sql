-- Private disappearing chat: text, photos and voice notes between the two partners.
--
-- Everything readable is sealed on the phone (`enc`, and the media bytes in the `chat` bucket):
-- the server only holds ciphertext plus who sent it, the kind and the timestamps. A message
-- disappears 5 minutes after the partner has seen it (`mark_chat_seen`); one never seen is
-- deleted after 7 days. A cron job deletes the rows each minute; their media files are queued
-- in `chat_media_trash` and removed from Storage by the `purge-chat` Edge Function (SQL cannot
-- delete Storage files). Apply after couple_games_slap.sql.

alter type public.notif_type add value if not exists 'chat';

-- ── Storage bucket for sealed photos and voice notes ───────────────────────────────────────
insert into storage.buckets (id, name, public) values ('chat', 'chat', false)
  on conflict (id) do nothing;

drop policy if exists chat_objects_rw on storage.objects;
create policy chat_objects_rw on storage.objects for all to authenticated
  using (bucket_id = 'chat' and public.is_active_couple_member(((storage.foldername(name))[1])::uuid))
  with check (bucket_id = 'chat' and public.is_active_couple_member(((storage.foldername(name))[1])::uuid));

-- ── Messages ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.chat_messages (
  id         uuid primary key,
  couple_id  uuid not null references public.couples (id) on delete cascade,
  sender_id  uuid references auth.users (id) on delete set null,
  kind       text not null check (kind in ('text', 'image', 'voice')),
  enc        text not null check (enc like 'u1:%' and char_length(enc) <= 8192),
  media_path text check (media_path is null or char_length(media_path) <= 200),
  created_at timestamptz not null default now(),
  seen_at    timestamptz,
  -- Unseen messages live a week; seeing one shortens that to 5 minutes (mark_chat_seen).
  expires_at timestamptz not null default now() + interval '7 days'
);
create index if not exists chat_messages_couple_idx  on public.chat_messages (couple_id, created_at);
create index if not exists chat_messages_sender_idx  on public.chat_messages (sender_id);
create index if not exists chat_messages_expires_idx on public.chat_messages (expires_at);

alter table public.chat_messages enable row level security;

drop policy if exists chat_messages_select on public.chat_messages;
create policy chat_messages_select on public.chat_messages for select to authenticated
  using (public.is_active_couple_member(couple_id));

-- Writes only through the RPCs below.
revoke all on public.chat_messages from anon, authenticated;
grant select on public.chat_messages to authenticated;

-- Full row on update events, so the partner's phone sees seen_at / expires_at change.
alter table public.chat_messages replica identity full;
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_messages') then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end $$;

-- Files of deleted messages wait here until purge-chat removes them from Storage. Nobody but the
-- service role touches it.
create table if not exists public.chat_media_trash (
  path       text primary key,
  created_at timestamptz not null default now()
);
alter table public.chat_media_trash enable row level security;
revoke all on public.chat_media_trash from anon, authenticated;

create or replace function public.chat_queue_media_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.media_path is not null then
    insert into public.chat_media_trash (path) values (old.media_path) on conflict do nothing;
  end if;
  return old;
end $$;
revoke all on function public.chat_queue_media_delete() from public, anon, authenticated;

drop trigger if exists chat_messages_media_trash on public.chat_messages;
create trigger chat_messages_media_trash after delete on public.chat_messages
  for each row execute function public.chat_queue_media_delete();

-- Sending a message counts as activity for the day streak.
drop trigger if exists chat_messages_activity on public.chat_messages;
create trigger chat_messages_activity after insert on public.chat_messages
  for each row execute function public.record_activity('sender_id');

-- ── RPCs ───────────────────────────────────────────────────────────────────────────────────
-- The id is chosen by the phone, so a retry after a lost answer cannot add a second message.
create or replace function public.send_chat_message(
  p_id uuid, p_couple uuid, p_kind text, p_enc text, p_media_path text)
returns uuid language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  if p_kind not in ('text', 'image', 'voice') then raise exception 'Invalid kind'; end if;
  -- Media lives at exactly <couple>/<message id>.enc; text has none. Nobody can point a message
  -- at another couple's file.
  if p_kind = 'text' then
    if p_media_path is not null then raise exception 'Invalid media'; end if;
  elsif p_media_path is distinct from (p_couple::text || '/' || p_id::text || '.enc') then
    raise exception 'Invalid media';
  end if;

  insert into public.chat_messages (id, couple_id, sender_id, kind, enc, media_path)
  values (p_id, p_couple, auth.uid(), p_kind, p_enc, p_media_path)
  on conflict (id) do nothing;

  -- A retry of an id that already exists must belong to this sender and couple.
  if not exists (select 1 from public.chat_messages
                  where id = p_id and couple_id = p_couple and sender_id = auth.uid()) then
    raise exception 'Invalid message';
  end if;
  return p_id;
end $$;

-- The receiver has seen these: they disappear 5 minutes from now. Only the partner of the sender
-- can do it, so you cannot start the timer on your own messages.
create or replace function public.mark_chat_seen(p_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update public.chat_messages m
     set seen_at = now(), expires_at = now() + interval '5 minutes'
   where m.id = any (p_ids)
     and m.seen_at is null
     and m.sender_id is distinct from auth.uid()
     and public.is_active_couple_member(m.couple_id);
end $$;

revoke all on function public.send_chat_message(uuid, uuid, text, text, text) from public, anon;
revoke all on function public.mark_chat_seen(uuid[])                          from public, anon;
grant execute on function public.send_chat_message(uuid, uuid, text, text, text) to authenticated;
grant execute on function public.mark_chat_seen(uuid[])                          to authenticated;

-- ── Expiry ─────────────────────────────────────────────────────────────────────────────────
-- Deletes what has expired, then asks purge-chat to remove the queued files from Storage.
create or replace function public.purge_chat()
returns void language plpgsql security definer set search_path = public, extensions, vault as $$
declare
  secret text;
begin
  delete from public.chat_messages where expires_at <= now();

  if not exists (select 1 from public.chat_media_trash) then return; end if;
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_webhook_secret';
  if secret is null then return; end if;
  perform net.http_post(
    url     := 'https://omatuaemysgykmdgsqvr.supabase.co/functions/v1/purge-chat',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    body    := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
exception when others then
  null; -- the next minute tries again
end $$;
revoke all on function public.purge_chat() from public, anon, authenticated;

create extension if not exists pg_cron;
select cron.unschedule('purge-chat') where exists (select 1 from cron.job where jobname = 'purge-chat');
select cron.schedule('purge-chat', '* * * * *', $$select public.purge_chat()$$);

-- Disconnecting (or deleting an account, which disconnects first) removes the couple's chat.
-- A trigger, so disconnect_couple / delete_my_account need not be re-created.
create or replace function public.chat_clear_on_disconnect()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.disconnected_at is not null and old.disconnected_at is null then
    delete from public.chat_messages where couple_id = new.id;
  end if;
  return new;
end $$;
revoke all on function public.chat_clear_on_disconnect() from public, anon, authenticated;

drop trigger if exists couples_chat_clear on public.couples;
create trigger couples_chat_clear after update of disconnected_at on public.couples
  for each row execute function public.chat_clear_on_disconnect();
