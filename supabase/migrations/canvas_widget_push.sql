-- Tells the partner's phone to redraw its home-screen doodle widget whenever the
-- shared canvas changes (strokes saved, or the canvas cleared). Sends a silent
-- data push through the `send-push` Edge Function; nothing is added to the
-- notifications inbox. Statement-level, so a saved batch of strokes is one call.
create or replace function public.notify_canvas_widget()
returns trigger language plpgsql security definer set search_path = public, extensions, vault as $$
declare
  secret text;
  cid    uuid;
  sender uuid;
begin
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_webhook_secret';
  if secret is null then return null; end if; -- not configured yet: never block the write

  if tg_op = 'INSERT' then
    select couple_id, user_id into cid, sender from new_rows limit 1;
  else
    select couple_id into cid from old_rows limit 1;
    sender := auth.uid();
  end if;
  if cid is null or sender is null then return null; end if;

  perform net.http_post(
    url     := 'https://omatuaemysgykmdgsqvr.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    body    := jsonb_build_object('record', jsonb_build_object(
                 'couple_id', cid, 'from_user_id', sender, 'type', 'canvasWidget')),
    timeout_milliseconds := 5000
  );
  return null;
exception when others then
  return null; -- a push failure must never fail a canvas write
end $$;

revoke all on function public.notify_canvas_widget() from public, anon, authenticated;

create trigger canvas_strokes_widget_insert
  after insert on public.canvas_strokes
  referencing new table as new_rows
  for each statement execute function public.notify_canvas_widget();

create trigger canvas_strokes_widget_delete
  after delete on public.canvas_strokes
  referencing old table as old_rows
  for each statement execute function public.notify_canvas_widget();
