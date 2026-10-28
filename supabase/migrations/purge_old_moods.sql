-- Keeps only the last 7 days of moods (the Home strip and weekly insights never look further back).
-- No scheduled job: whenever a mood is added, that couple's moods older than 7 days are deleted
-- in the same transaction, using the (couple_id, sent_at) index.
-- Each user's latest mood is kept, so the partner's "current" mood does not vanish after a quiet week.

create or replace function public.purge_old_moods_for_couple()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.moods m
   where m.couple_id = new.couple_id
     and m.sent_at < now() - interval '7 days'
     and m.id not in (
       select distinct on (user_id) id
         from public.moods
        where couple_id = new.couple_id
        order by user_id, sent_at desc);
  return null;
end $$;

revoke all on function public.purge_old_moods_for_couple() from public, anon, authenticated;

drop trigger if exists purge_old_moods on public.moods;
create trigger purge_old_moods
  after insert on public.moods
  for each row execute function public.purge_old_moods_for_couple();
