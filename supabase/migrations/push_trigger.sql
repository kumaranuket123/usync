-- Calls the `send-push` Edge Function whenever a notification row is created.
-- The shared secret is generated inside the database and stored in Vault
-- (name: push_webhook_secret); it never appears in code or in any client.
create extension if not exists pg_net with schema extensions;

select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'push_webhook_secret')
where not exists (select 1 from vault.decrypted_secrets where name = 'push_webhook_secret');

-- Lets the Edge Function (service role only) read the secret to authenticate the trigger's calls.
create or replace function public.push_webhook_secret()
returns text language sql security definer set search_path = vault as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'push_webhook_secret';
$$;
revoke all on function public.push_webhook_secret() from public, anon, authenticated;
grant execute on function public.push_webhook_secret() to service_role;

create or replace function public.notify_push()
returns trigger language plpgsql security definer set search_path = public, extensions, vault as $$
declare
  secret text;
begin
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_webhook_secret';
  if secret is null then return new; end if; -- not configured yet: skip, never block the insert

  perform net.http_post(
    url     := 'https://omatuaemysgykmdgsqvr.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    body    := jsonb_build_object('record', to_jsonb(new)),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  return new; -- a push failure must never fail the notification insert
end $$;

revoke all on function public.notify_push() from public, anon, authenticated;

create trigger notifications_push
  after insert on public.notifications
  for each row execute function public.notify_push();
