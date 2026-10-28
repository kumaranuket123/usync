-- End-to-end encryption, phase E5a: sealing the content that was written before encryption.
--
-- Each phone seals the rows IT wrote (it is the only one that knows they are its own), by sending the
-- sealed value to these functions. A function only accepts it for the caller's own row, only while the row
-- is still readable, and replaces the readable content with the same placeholders new rows use. The server
-- cannot check what is inside the sealed value; the point is that the readable text is gone afterwards.
--
-- Locations and the next-meeting date already have their own paths (the next location refresh, and
-- set_next_meet_enc), so they are not here.

create or replace function public.seal_row(p_table text, p_id uuid, p_enc text, p_image_path text default null)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare
  me uuid := auth.uid();
  n  int  := 0;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if p_table is null or p_id is null or p_enc is null
     or char_length(p_enc) > 262144 or p_enc !~ '^u1:[A-Za-z0-9_=-]+$' then
    raise exception 'Invalid request';
  end if;

  if p_table = 'moods' then
    update public.moods
       set enc = p_enc, type = 'custom', custom_label = null, custom_emoji = null
     where id = p_id and user_id = me and enc is null and public.is_active_couple_member(couple_id);
  elsif p_table = 'bucket_items' then
    update public.bucket_items
       set enc = p_enc, title = '🔒', emoji = '🔒', note = null
     where id = p_id and created_by = me and enc is null and public.is_active_couple_member(couple_id);
  elsif p_table = 'memories' then
    -- The new picture path (the sealed copy the phone uploaded) must be in the couple's own folder.
    update public.memories
       set enc = p_enc, title = '🔒', thumbnail_emoji = '🔒',
           thumbnail_url = case
             when p_image_path is not null and p_image_path = couple_id::text || '/' || id::text || '.enc' then p_image_path
             else thumbnail_url end
     where id = p_id and created_by_user_id = me and enc is null and public.is_active_couple_member(couple_id);
  elsif p_table = 'milestones' then
    update public.milestones
       set enc = p_enc, title = '🔒', note = null, emoji = null, repeats_yearly = false,
           occurred_at = timestamptz '1970-01-01 12:00:00+00'
     where id = p_id and created_by = me and type = 'custom' and enc is null and public.is_active_couple_member(couple_id);
  elsif p_table = 'canvas_strokes' then
    update public.canvas_strokes
       set enc = p_enc, color = null, width = null, points = null, is_eraser = false
     where id = p_id and user_id = me and enc is null and public.is_active_couple_member(couple_id);
  else
    raise exception 'Invalid request';
  end if;

  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public.seal_row(text, uuid, text, text) from public, anon;
grant execute on function public.seal_row(text, uuid, text, text) to authenticated;

-- A daily-question answer has no id of its own: it is the caller's answer for one day.
create or replace function public.seal_answer(p_couple uuid, p_day date, p_enc text)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_couple is null or p_day is null or p_enc is null
     or char_length(p_enc) > 4096 or p_enc !~ '^u1:[A-Za-z0-9_=-]+$' then
    raise exception 'Invalid request';
  end if;
  update public.question_answers set answer = p_enc
   where couple_id = p_couple and user_id = auth.uid() and day = p_day
     and answer not like 'u1:%' and public.is_active_couple_member(couple_id);
  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public.seal_answer(uuid, date, text) from public, anon;
grant execute on function public.seal_answer(uuid, date, text) to authenticated;
