-- Only a couple's newest 10 memory pictures stay on the server. Older ones are
-- saved on both phones first; the server copy is deleted only once BOTH partners
-- have confirmed they hold a local copy, so nobody loses a picture.
alter table public.memories
  add column if not exists archived_by    uuid[]  not null default '{}',
  add column if not exists image_archived boolean not null default false;

-- Records that the caller holds a local copy. Returns true when both partners do.
create or replace function public.archive_memory_image(p_memory uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  m public.memories;
  c public.couples;
begin
  select * into m from public.memories where id = p_memory;
  if not found or not public.is_active_couple_member(m.couple_id) then
    raise exception 'Not allowed';
  end if;

  if not (auth.uid() = any (m.archived_by)) then
    update public.memories set archived_by = array_append(archived_by, auth.uid())
      where id = p_memory returning * into m;
  end if;

  select * into c from public.couples where id = m.couple_id;
  return c.user_a_id = any (m.archived_by) and c.user_b_id = any (m.archived_by);
end $$;

-- Called after the server copy of the image is deleted: the row keeps its title
-- and date but no longer points at a file.
create or replace function public.finish_memory_archive(p_memory uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  m public.memories;
  c public.couples;
begin
  select * into m from public.memories where id = p_memory;
  if not found or not public.is_active_couple_member(m.couple_id) then
    raise exception 'Not allowed';
  end if;
  select * into c from public.couples where id = m.couple_id;
  if not (c.user_a_id = any (m.archived_by) and c.user_b_id = any (m.archived_by)) then
    raise exception 'Both partners must hold a copy first';
  end if;
  update public.memories set thumbnail_url = null, image_archived = true where id = p_memory;
end $$;

revoke all on function public.archive_memory_image(uuid), public.finish_memory_archive(uuid) from public, anon;
grant execute on function public.archive_memory_image(uuid), public.finish_memory_archive(uuid) to authenticated;
