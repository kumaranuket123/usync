-- Chat as a mailbox (WhatsApp / Signal model): the server only carries a message until the partner's
-- phone has it. The phone saves it, then calls ack_chat_messages, which deletes the row (the media
-- trash trigger then queues the sealed photo / voice file for removal). History lives on the phones.
--
-- Also adds `control` envelopes (sealed like messages): read / delivered receipts, "delete for
-- everyone" and "clear for both" travel the same way, so they reach a phone that was offline.
-- The vanish timer becomes optional: 0 = off (the new default). It runs on each phone, from the moment
-- the message is read, so the server no longer takes part in it.
--
-- Apply after couple_chat_shared_timer.sql. OLD APP BUILDS DO NOT WORK WITH THIS (they rely on
-- mark_chat_seen and on rows staying until their timer ends): raise the minimum build in
-- app_config first or together with it.

-- ── Kinds, timer values ──────────────────────────────────────────────────────────────────────
alter table public.chat_messages drop constraint if exists chat_messages_kind_check;
alter table public.chat_messages add constraint chat_messages_kind_check
  check (kind in ('text', 'image', 'voice', 'control'));

alter table public.chat_messages drop constraint if exists chat_messages_ttl_allowed;
alter table public.chat_messages add constraint chat_messages_ttl_allowed
  check (ttl_seconds in (0, 10, 60, 300, 3600, 86400));

alter table public.couples drop constraint if exists couples_chat_ttl_allowed;
alter table public.couples add constraint couples_chat_ttl_allowed
  check (chat_ttl_seconds in (0, 10, 60, 300, 3600, 86400));
alter table public.couples alter column chat_ttl_seconds set default 0;
-- 1 day was only ever the default, not a choice: those couples go to Off. Any other value was chosen.
update public.couples set chat_ttl_seconds = 0 where chat_ttl_seconds = 86400;

create or replace function public.set_chat_timer(p_couple uuid, p_seconds integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  if p_seconds not in (0, 10, 60, 300, 3600, 86400) then raise exception 'Invalid timer'; end if;
  update public.couples set chat_ttl_seconds = p_seconds where id = p_couple;
end $$;

-- ── Tombstones ───────────────────────────────────────────────────────────────────────────────
-- Once a row is gone (collected, deleted, cleared) the server must still tell "already delivered" from
-- "never sent", or a retry of a lost answer would put the message (or a delete / clear control) back.
-- Only the ids are kept, for as long as a row could have waited (14 days).
create table if not exists public.chat_tombstones (
  id         uuid primary key,
  created_at timestamptz not null default now()
);
create index if not exists chat_tombstones_created_idx on public.chat_tombstones (created_at);
alter table public.chat_tombstones enable row level security;
revoke all on public.chat_tombstones from anon, authenticated;

create or replace function public.chat_tombstone()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.chat_tombstones (id) values (old.id) on conflict do nothing;
  return old;
end $$;
revoke all on function public.chat_tombstone() from public, anon, authenticated;

drop trigger if exists chat_messages_tombstone on public.chat_messages;
create trigger chat_messages_tombstone after delete on public.chat_messages
  for each row execute function public.chat_tombstone();

-- The expiry job also forgets old tombstones.
create or replace function public.purge_chat()
returns void language plpgsql security definer set search_path = public, extensions, vault as $$
declare
  secret text;
begin
  delete from public.chat_messages where expires_at <= now();
  delete from public.chat_tombstones where created_at < now() - interval '15 days';

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

-- Receipts are not activity: only real messages count for the day streak.
drop trigger if exists chat_messages_activity on public.chat_messages;
create trigger chat_messages_activity after insert on public.chat_messages
  for each row when (new.kind <> 'control') execute function public.record_activity('sender_id');

-- ── Sending ──────────────────────────────────────────────────────────────────────────────────
-- Returns when the server received it: the phone orders its own message by this time, like the partner's.
drop function if exists public.send_chat_message(uuid, uuid, text, text, text, integer);
create function public.send_chat_message(
  p_id uuid, p_couple uuid, p_kind text, p_enc text, p_media_path text, p_ttl integer default 0)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  ttl int;
  sent timestamptz;
begin
  if auth.uid() is null or not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  if p_kind not in ('text', 'image', 'voice', 'control') then raise exception 'Invalid kind'; end if;
  if p_ttl not in (0, 10, 60, 300, 3600, 86400) then raise exception 'Invalid timer'; end if;
  if p_kind in ('text', 'control') then
    if p_media_path is not null then raise exception 'Invalid media'; end if;
  elsif p_media_path is distinct from (p_couple::text || '/' || p_id::text || '.enc') then
    raise exception 'Invalid media';
  end if;

  -- Already delivered (or deleted / cleared) and this is a retry: nothing to put back.
  if exists (select 1 from public.chat_tombstones where id = p_id) then return now(); end if;
  if exists (select 1 from public.chat_messages where id = p_id
              and (couple_id <> p_couple or sender_id is distinct from auth.uid())) then
    raise exception 'Invalid message';
  end if;

  select chat_ttl_seconds into ttl from public.couples where id = p_couple;

  -- A message nobody collects is dropped after 14 days.
  insert into public.chat_messages (id, couple_id, sender_id, kind, enc, media_path, ttl_seconds, expires_at)
  values (p_id, p_couple, auth.uid(), p_kind, p_enc, p_media_path, coalesce(ttl, 0), now() + interval '14 days')
  on conflict (id) do nothing;

  select created_at into sent from public.chat_messages where id = p_id;
  return coalesce(sent, now());
end $$;

revoke all on function public.send_chat_message(uuid, uuid, text, text, text, integer) from public, anon;
grant execute on function public.send_chat_message(uuid, uuid, text, text, text, integer) to authenticated;

-- ── Collecting ───────────────────────────────────────────────────────────────────────────────
-- The recipient has these on their phone: delete them from the server. Only the partner of the sender
-- can do it (the sender deletes their own undelivered ones with delete_chat_message).
create or replace function public.ack_chat_messages(p_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if cardinality(p_ids) > 1000 then raise exception 'Too many'; end if;
  delete from public.chat_messages m
   where m.id = any (p_ids)
     and m.sender_id is distinct from auth.uid()
     and public.is_active_couple_member(m.couple_id);
end $$;

revoke all on function public.ack_chat_messages(uuid[]) from public, anon;
grant execute on function public.ack_chat_messages(uuid[]) to authenticated;

-- The timer now runs on the phones.
drop function if exists public.mark_chat_seen(uuid[]);

-- ── Taking back, clearing ────────────────────────────────────────────────────────────────────
-- Taking back an undelivered message: only its sender (the recipient collects with ack_chat_messages).
create or replace function public.delete_chat_message(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  delete from public.chat_messages m
   where m.id = p_id and m.sender_id = auth.uid() and public.is_active_couple_member(m.couple_id);
end $$;

-- Clearing the mailbox leaves control envelopes alone: a "delete for everyone" / receipt still on its
-- way to a phone that has not collected it must arrive.
create or replace function public.clear_chat(p_couple uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  delete from public.chat_messages where couple_id = p_couple and kind <> 'control';
end $$;
