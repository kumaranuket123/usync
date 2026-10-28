-- End-to-end encryption, phase E3c: locations.
--
-- A person's location keeps its latitude, longitude, accuracy and the time of the fix ONLY in the encrypted
-- column `enc` (bound to the person's row). The readable columns are cleared. Older rows keep their readable
-- columns until the next refresh or phase E5, so readers accept both. `allow_background` stays readable (the
-- push function needs it) and so does `updated_at`.

alter table public.locations
  add column if not exists enc text check (enc is null or (enc like 'u1:%' and char_length(enc) <= 4096));
-- The app saves with an upsert (insert, or update on conflict), so both grants are needed.
grant insert (enc), update (enc) on public.locations to authenticated;

alter table public.locations alter column latitude  drop not null;
alter table public.locations alter column longitude drop not null;
alter table public.locations alter column accuracy  drop not null;

-- Every location carries its content one way or the other.
alter table public.locations drop constraint if exists locations_content;
alter table public.locations add constraint locations_content
  check (enc is not null or (latitude is not null and longitude is not null and accuracy is not null));
