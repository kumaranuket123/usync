-- Expired invite codes are deleted. A code is removed an hour after it expires (not at the instant), so
-- someone typing a just-expired code still gets "Invite code expired" rather than "Invalid invite code".
-- Runs once a month, on the last day. Used codes are already deleted by join_with_code.

create or replace function public.purge_expired_invite_codes()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with gone as (
    delete from public.invite_codes where expires_at < now() - interval '1 hour' returning 1
  )
  select count(*) into n from gone;
  return n;
end $$;

revoke all on function public.purge_expired_invite_codes() from public, anon, authenticated;

create extension if not exists pg_cron;

-- pg_cron has no "last day of the month", so it fires on the 28th-31st at 23:55 UTC and the job only
-- does something when tomorrow is the 1st.
create or replace function public.purge_expired_invite_codes_monthly()
returns int language plpgsql security definer set search_path = public as $$
begin
  if (current_date + 1) <> date_trunc('month', current_date + 1)::date then return 0; end if;
  return public.purge_expired_invite_codes();
end $$;

revoke all on function public.purge_expired_invite_codes_monthly() from public, anon, authenticated;

select cron.unschedule('purge-expired-invite-codes')
 where exists (select 1 from cron.job where jobname = 'purge-expired-invite-codes');
select cron.schedule('purge-expired-invite-codes', '55 23 28-31 * *', $$select public.purge_expired_invite_codes_monthly()$$);

-- One-off: today's backlog.
select public.purge_expired_invite_codes();
