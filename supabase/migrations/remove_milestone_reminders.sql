-- Apply this ONLY when the app build that schedules reminders on the phone is the minimum supported build
-- (`app_config.min_supported_build`). Until then the server job is what reminds people of readable dates.
--
-- Reminders for timeline dates are now local notifications scheduled by each phone, because the server can
-- no longer read the dates (they are end-to-end encrypted). Leaving the job would remind people twice.

select cron.unschedule('milestone-reminders')
 where exists (select 1 from cron.job where jobname = 'milestone-reminders');
drop function if exists public.send_milestone_reminders(date);
