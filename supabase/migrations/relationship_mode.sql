-- Relationship mode: whether the couple lives apart ('long_distance') or
-- together ('together'). Shared by both partners and changeable at any time by
-- either of them; the app uses it to pick mode-specific content (for now the
-- question-of-the-day bank). Like every couple state change it goes through an
-- RPC, never a direct write.

alter table public.couples
  add column if not exists relationship_mode text not null default 'together'
  check (relationship_mode in ('together', 'long_distance'));

create or replace function public.set_relationship_mode(p_couple uuid, p_mode text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active_couple_member(p_couple) then raise exception 'Not a member'; end if;
  if p_mode not in ('together', 'long_distance') then raise exception 'Invalid mode'; end if;
  update public.couples set relationship_mode = p_mode where id = p_couple;
end $$;

revoke all on function public.set_relationship_mode(uuid, text) from public, anon;
grant execute on function public.set_relationship_mode(uuid, text) to authenticated;
