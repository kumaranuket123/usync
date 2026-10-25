-- One push token per DEVICE instead of one per account.
--
-- Before: device_tokens had one row per user (primary key user_id), so a second
-- phone replaced the first one's token, and signing out on one phone removed
-- pushes for both. Now each device has its own row (primary key fcm_token) and a
-- push goes to every device the recipient is signed in on.
--
-- Step 1 of 2: additive and compatible with the app builds already out there.
-- Step 2 (drop_device_silent_types.sql) removes the old column once the new
-- push function is live.

-- The alert-sound choices belong to a person, not to a phone, so they move to
-- the profile (a user edits only their own row; see profiles_update_own).
alter table public.profiles
  add column if not exists silent_types text[] not null default array['location'];
grant update (silent_types) on public.profiles to authenticated;

update public.profiles p
   set silent_types = d.silent_types
  from public.device_tokens d
 where d.user_id = p.id;

-- One row per device. A token identifies one app install, so it is the key.
alter table public.device_tokens drop constraint device_tokens_pkey;
alter table public.device_tokens add primary key (fcm_token);
create index if not exists device_tokens_user_id_idx on public.device_tokens (user_id);

-- Registers the calling device for the signed-in user. A function rather than a
-- plain upsert because a phone that changes hands (one account signs out, another
-- signs in, same token) must reassign the existing row, which row-level security
-- would otherwise refuse (the row still belongs to the previous account).
-- Keeps the 5 most recently registered devices per account.
create or replace function public.register_device_token(p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or coalesce(p_token, '') = '' then return; end if;

  insert into public.device_tokens (fcm_token, user_id)
  values (p_token, auth.uid())
  on conflict (fcm_token) do update
    set user_id = excluded.user_id, updated_at = now();

  delete from public.device_tokens
   where user_id = auth.uid()
     and fcm_token not in (
       select fcm_token from public.device_tokens
        where user_id = auth.uid()
        order by updated_at desc
        limit 5);
end;
$$;
revoke all on function public.register_device_token(text) from public, anon;
grant execute on function public.register_device_token(text) to authenticated;
