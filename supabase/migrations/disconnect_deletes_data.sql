-- Disconnecting now deletes everything the couple shared: moods, memories,
-- timeline, notifications, canvas strokes, locations and streak activity.
-- The `couples` row stays as an empty tombstone (disconnected_at set) so the
-- partner's app still sees the disconnect through its Realtime subscription.
-- Memory image files in Storage are removed by the app before this runs
-- (Storage objects cannot be deleted from SQL).
create or replace function public.disconnect_couple(p_couple uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.couples;
begin
  select * into c from public.couples where id = p_couple for update;
  if not found or auth.uid() not in (c.user_a_id, c.user_b_id) then raise exception 'Not a member'; end if;
  if c.disconnected_at is not null then return; end if;

  delete from public.moods           where couple_id = p_couple;
  delete from public.memories        where couple_id = p_couple;
  delete from public.milestones      where couple_id = p_couple;
  delete from public.notifications   where couple_id = p_couple;
  delete from public.canvas_strokes  where couple_id = p_couple;
  delete from public.locations       where couple_id = p_couple;
  delete from public.couple_activity where couple_id = p_couple;

  update public.couples
     set disconnected_at = now(), disconnect_requested_by = null,
         streak_days = 0, streak_last_day = null, total_moments = 0
   where id = p_couple;
  update public.profiles set couple_id = null where couple_id = p_couple;
end $$;
