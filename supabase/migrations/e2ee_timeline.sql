-- End-to-end encryption, phase E4a: timeline dates.
--
-- A custom date keeps its title, note, emoji, day and "every year" flag ONLY in the encrypted column `enc`
-- (bound to the row). The readable columns hold placeholders. Rows the server itself writes (streak and
-- first-connect milestones) and older readable dates stay as they are; readers accept both.
--
-- The server-side reminder job reads those readable columns, so it now skips sealed dates. Phones schedule
-- reminders themselves (local notifications); once that build is the minimum, the job is removed by
-- `remove_milestone_reminders.sql`.

alter table public.milestones
  add column if not exists enc text check (enc is null or (enc like 'u1:%' and char_length(enc) <= 4096));
-- This table grants INSERT per column, so the new column needs its own grant.
grant insert (enc) on public.milestones to authenticated;

create or replace function public.send_milestone_reminders(
  for_day date default (now() at time zone 'utc')::date
) returns integer
language plpgsql security definer set search_path = public as $$
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
      and ms.enc is null                       -- sealed dates are reminded by the phones
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
