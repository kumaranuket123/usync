-- End-to-end encryption, phase E5b: lock-down. APPLY ONLY AT RELEASE, when `app_config.min_supported_build`
-- is the build that seals everything (older builds write readable content and would be refused).
--
-- From now on the server refuses new content that is not sealed, and clients can no longer write readable
-- text into the old columns. Older readable rows are not touched here (their authors seal them with
-- `seal_row`); a row whose author never comes back simply stays as it was.

-- ── New rows must be sealed, with the same placeholders the app writes ──────────────────────────────
create or replace function public.require_sealed()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  case tg_table_name
    when 'moods' then
      if new.enc is null or new.type <> 'custom' or new.custom_label is not null or new.custom_emoji is not null then
        raise exception 'Content must be encrypted';
      end if;
    when 'bucket_items' then
      if new.enc is null or new.title <> '🔒' or new.emoji <> '🔒' or new.note is not null then
        raise exception 'Content must be encrypted';
      end if;
    when 'memories' then
      if new.enc is null or new.title <> '🔒' or new.thumbnail_emoji <> '🔒' then
        raise exception 'Content must be encrypted';
      end if;
    when 'milestones' then
      -- Only custom dates carry private text; the server writes the others itself.
      if new.type = 'custom' and (new.enc is null or new.title <> '🔒' or new.note is not null
                                  or new.emoji is not null or new.repeats_yearly) then
        raise exception 'Content must be encrypted';
      end if;
    when 'canvas_strokes' then
      if new.enc is null or new.color is not null or new.width is not null or new.points is not null then
        raise exception 'Content must be encrypted';
      end if;
    when 'locations' then
      if new.enc is null or new.latitude is not null or new.longitude is not null or new.accuracy is not null then
        raise exception 'Content must be encrypted';
      end if;
    when 'question_answers' then
      if new.answer not like 'u1:%' then raise exception 'Content must be encrypted'; end if;
  end case;
  return new;
end $$;
revoke all on function public.require_sealed() from public, anon, authenticated;

drop trigger if exists require_sealed_insert on public.moods;
create trigger require_sealed_insert before insert on public.moods
  for each row execute function public.require_sealed();
drop trigger if exists require_sealed_insert on public.bucket_items;
create trigger require_sealed_insert before insert on public.bucket_items
  for each row execute function public.require_sealed();
drop trigger if exists require_sealed_insert on public.memories;
create trigger require_sealed_insert before insert on public.memories
  for each row execute function public.require_sealed();
drop trigger if exists require_sealed_insert on public.milestones;
create trigger require_sealed_insert before insert on public.milestones
  for each row execute function public.require_sealed();
drop trigger if exists require_sealed_insert on public.canvas_strokes;
create trigger require_sealed_insert before insert on public.canvas_strokes
  for each row execute function public.require_sealed();
drop trigger if exists require_sealed_insert on public.question_answers;
create trigger require_sealed_insert before insert on public.question_answers
  for each row execute function public.require_sealed();
-- A location is saved with an upsert, so the update path is checked too.
drop trigger if exists require_sealed_write on public.locations;
create trigger require_sealed_write before insert or update of latitude, longitude, accuracy, enc on public.locations
  for each row execute function public.require_sealed();

-- ── Clients can no longer rewrite the readable columns of existing rows ─────────────────────────────
-- Content changes only through seal_row / seal_answer / set_next_meet_enc. What the app still updates
-- directly (favourites, ticking a bucket item, locations) keeps its grants.
revoke update on public.moods            from authenticated;
revoke update (title, emoji, note) on public.bucket_items from authenticated;
revoke update (title, note, emoji, repeats_yearly, occurred_at) on public.milestones from authenticated;
revoke update on public.canvas_strokes   from authenticated;
revoke update on public.question_answers from authenticated;

-- ── The readable next-meeting date: the old RPC wrote it in the clear ──────────────────────────────
drop function if exists public.set_next_meet(uuid, date);

-- ── Old notifications quoted the sender's name and what people typed ───────────────────────────────
-- Everything written before the sealed detail existed carries a name (and often moods, titles or dates) in
-- its text. The kind of activity and the time stay; the words go.
update public.notifications
   set body_text = 'Activity from before encryption'
 where detail_enc is null and created_at < now();
