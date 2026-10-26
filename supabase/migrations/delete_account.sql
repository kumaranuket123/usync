-- In-app account deletion (required by Google Play for apps with accounts).
--
-- The couple row has to survive as an empty, disconnected tombstone so the partner's
-- app still learns about it through Realtime, so its member columns become nullable
-- and are cleared (not blocked) when a user is removed.
alter table public.couples
  alter column user_a_id drop not null,
  alter column user_b_id drop not null,
  drop constraint couples_user_a_id_fkey,
  drop constraint couples_user_b_id_fkey,
  drop constraint couples_disconnect_requested_by_fkey,
  add  constraint couples_user_a_id_fkey foreign key (user_a_id) references auth.users (id) on delete set null,
  add  constraint couples_user_b_id_fkey foreign key (user_b_id) references auth.users (id) on delete set null,
  add  constraint couples_disconnect_requested_by_fkey foreign key (disconnect_requested_by) references auth.users (id) on delete set null;

-- Deletes the caller's account and everything shared in every couple they were in
-- (current or past), then the auth user itself. The partner is left disconnected.
-- Memory images in Storage are removed by the app first (SQL cannot delete them).
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  cid uuid;
begin
  if uid is null then raise exception 'Not signed in'; end if;

  for cid in select id from public.couples where uid in (user_a_id, user_b_id) loop
    delete from public.moods           where couple_id = cid;
    delete from public.memories        where couple_id = cid;
    delete from public.milestones      where couple_id = cid;
    delete from public.notifications   where couple_id = cid;
    delete from public.canvas_strokes  where couple_id = cid;
    delete from public.locations       where couple_id = cid;
    delete from public.couple_activity where couple_id = cid;

    update public.couples
       set disconnected_at = coalesce(disconnected_at, now()), disconnect_requested_by = null,
           streak_days = 0, streak_last_day = null, total_moments = 0
     where id = cid;
    update public.profiles set couple_id = null where couple_id = cid;
  end loop;

  -- Profile, device tokens, invite codes, location and sessions go with the user (cascade).
  delete from auth.users where id = uid;
end $$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
