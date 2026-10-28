-- Removes `couples` tombstones (rows left behind by disconnect_couple) once they are
-- old enough that the partner's app has long since seen the disconnect. disconnect_couple
-- already deleted everything the couple shared, so only the empty row is removed here.
-- Rows that still own shared data are skipped, so nothing is purged before it is cleared.

create or replace function public.purge_old_disconnected_couples(p_days int default 30)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with gone as (
    delete from public.couples c
     where c.disconnected_at is not null
       and c.disconnected_at < now() - make_interval(days => p_days)
       and not exists (select 1 from public.profiles p where p.couple_id = c.id)
       and not exists (select 1 from public.moods x where x.couple_id = c.id)
       and not exists (select 1 from public.memories x where x.couple_id = c.id)
       and not exists (select 1 from public.milestones x where x.couple_id = c.id)
       and not exists (select 1 from public.notifications x where x.couple_id = c.id)
       and not exists (select 1 from public.canvas_strokes x where x.couple_id = c.id)
       and not exists (select 1 from public.locations x where x.couple_id = c.id)
       and not exists (select 1 from public.couple_activity x where x.couple_id = c.id)
       and not exists (select 1 from public.question_answers x where x.couple_id = c.id)
       and not exists (select 1 from public.bucket_items x where x.couple_id = c.id)
    returning 1)
  select count(*) into n from gone;
  return n;
end $$;

revoke all on function public.purge_old_disconnected_couples(int) from public, anon, authenticated;

create extension if not exists pg_cron;

select cron.unschedule('purge-old-disconnected-couples')
 where exists (select 1 from cron.job where jobname = 'purge-old-disconnected-couples');
select cron.schedule('purge-old-disconnected-couples', '0 3 * * *',
                     $$select public.purge_old_disconnected_couples(30)$$);
