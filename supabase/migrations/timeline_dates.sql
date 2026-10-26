-- Special dates on the relationship timeline ("our first date", "engagement day").
-- Either partner can add them (the existing milestones_write policy); on the day
-- both partners get a notification, every year if the date repeats.
--
-- The date is stored as noon UTC of the chosen day, so it shows as the same
-- calendar day in any timezone from UTC-12 to UTC+11.
alter table public.milestones
  add column if not exists emoji            text,
  add column if not exists repeats_yearly   boolean not null default false,
  add column if not exists created_by       uuid references auth.users (id) on delete set null,
  add column if not exists last_notified_on date;

-- Notifies both partners about every custom date that falls on [for_day].
-- Notifications are stored by sender and delivered to the sender's partner, so
-- one row from each partner reaches both of them. last_notified_on makes a
-- second run on the same day a no-op.
create or replace function public.send_milestone_reminders(
  for_day date default (now() at time zone 'utc')::date
) returns int language plpgsql security definer set search_path = public as $$
declare
  m     record;
  a     uuid;
  b     uuid;
  years int;
  body  text;
  sent  int := 0;
begin
  for m in
    select ms.*, (ms.occurred_at at time zone 'utc')::date as event_day
    from public.milestones ms
    where ms.type = 'custom'
      and ms.last_notified_on is distinct from for_day
      and (ms.occurred_at at time zone 'utc')::date <= for_day
      and (
        (ms.occurred_at at time zone 'utc')::date = for_day
        or (ms.repeats_yearly
            and to_char((ms.occurred_at at time zone 'utc')::date, 'MM-DD') = to_char(for_day, 'MM-DD'))
      )
  loop
    select user_a_id, user_b_id into a, b
    from public.couples where id = m.couple_id and disconnected_at is null;
    if not found then continue; end if;

    years := extract(year from for_day)::int - extract(year from m.event_day)::int;
    body := case
      when m.repeats_yearly and years > 0 then
        format('%s %s — %s %s today!', coalesce(m.emoji, '✨'), m.title, years,
               case when years = 1 then 'year' else 'years' end)
      else format('%s Today: %s', coalesce(m.emoji, '✨'), m.title)
    end;

    insert into public.notifications (couple_id, from_user_id, type, body_text)
    values (m.couple_id, a, 'milestone', body),
           (m.couple_id, b, 'milestone', body);

    update public.milestones set last_notified_on = for_day where id = m.id;
    sent := sent + 1;
  end loop;
  return sent;
end;
$$;
revoke all on function public.send_milestone_reminders(date) from public, anon, authenticated;

-- Every day at 03:30 UTC (9:00 am in India).
create extension if not exists pg_cron;
select cron.schedule('milestone-reminders', '30 3 * * *', $$select public.send_milestone_reminders()$$);
