-- End-to-end encryption: "start fresh" for a couple that lost every copy of its couple key (both phones were
-- reinstalled and nobody has the recovery phrase). Nobody can open the sealed history any more, so either
-- partner may clear it and let the phones make a new key.
--
-- Only what is sealed goes (it cannot be read by anyone). Older readable rows are left for their authors to
-- seal. Memory pictures are removed from Storage by the app first (SQL cannot remove the files).

create or replace function public.start_fresh_encryption(p_couple uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.couples;
begin
  select * into c from public.couples where id = p_couple for update;
  if not found or c.disconnected_at is not null or auth.uid() is null
     or auth.uid() not in (c.user_a_id, c.user_b_id) then
    raise exception 'Not a member';
  end if;

  delete from public.moods            where couple_id = p_couple and enc is not null;
  delete from public.bucket_items     where couple_id = p_couple and enc is not null;
  delete from public.memories         where couple_id = p_couple and enc is not null;
  delete from public.milestones       where couple_id = p_couple and enc is not null;
  delete from public.canvas_strokes   where couple_id = p_couple and enc is not null;
  delete from public.question_answers where couple_id = p_couple and answer like 'u1:%';
  delete from public.locations        where couple_id = p_couple and enc is not null;
  update public.notifications set detail_enc = null where couple_id = p_couple and detail_enc is not null;
  update public.couples       set next_meet_enc = null where id = p_couple;

  -- Last, so that nobody can create a new key while old rows are still there.
  delete from public.couple_keys where couple_id = p_couple;
end $$;
revoke all on function public.start_fresh_encryption(uuid) from public, anon;
grant execute on function public.start_fresh_encryption(uuid) to authenticated;
