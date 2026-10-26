-- Keep only the 10 newest notifications each user receives. Rows are stored by
-- sender, and the recipient is the sender's partner, so one (couple, sender)
-- group is exactly one person's inbox. Runs after every insert, so old ones
-- disappear as new ones arrive.
create or replace function public.trim_notifications()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.notifications n
  where n.couple_id = new.couple_id
    and n.from_user_id = new.from_user_id
    and n.id not in (
      select id from public.notifications
      where couple_id = new.couple_id and from_user_id = new.from_user_id
      order by created_at desc, id desc limit 10);
  return null;
end;
$$;
revoke all on function public.trim_notifications() from public, anon, authenticated;

create trigger notifications_trim after insert on public.notifications
  for each row execute function public.trim_notifications();

-- One-time cleanup of what is already stored.
delete from public.notifications
where id in (
  select id from (
    select id, row_number() over (
      partition by couple_id, from_user_id order by created_at desc, id desc) as rn
    from public.notifications) t
  where rn > 10);
