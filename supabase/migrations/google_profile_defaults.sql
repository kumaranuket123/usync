-- Google sign-in: use the Google display name for new profiles (falls back to
-- the email prefix). Apply to the project as a migration.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, email, avatar_emoji)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'username', ''),
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(new.raw_user_meta_data ->> 'name', ''),
      split_part(new.email, '@', 1)
    ),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'avatar_emoji', '🦋')
  );
  return new;
end $$;
