-- Groundwork for a future subscription. Nothing changes for anyone yet:
-- `paywall_enabled` starts false, so every couple has full access.
--
-- 1. app_config: one row of switches the app reads before sign-in (minimum
--    supported build for a "please update" screen, the paywall switch, trial length).
-- 2. Grandfathering: every profile that exists when this migration runs is marked
--    grandfathered. It lives on the PERSON, not the couple, because disconnecting
--    and re-pairing creates a new couple row (and would otherwise lose it, or let
--    someone restart a trial). Anyone who joined later but before launch can be
--    covered by setting app_config.grandfather_before to the launch time: every
--    profile created before it counts as grandfathered.
-- 3. Trial: counted from account creation (profiles.created_at + trial_days), also
--    per person, so re-pairing cannot restart it. A couple's trial runs from its
--    newest member.
-- 4. profiles.premium_until: the payer's paid-until date, set only by a verified
--    payment webhook (a later step; clients can update only username, avatar_emoji
--    and silent_types on profiles). It lives on the person for the same reason as
--    grandfathering, and covers the whole couple while that person is in it.
-- 5. couple_access / get_access: the one place that decides free / grandfathered /
--    premium / trial / expired.
--
-- Known limits (product decisions for later, none matters while paywall_enabled is false):
--  - Deleting an account and signing up again with the same Google account creates a
--    NEW profile: it loses grandfathering and gets a fresh trial. Closing that needs
--    something that survives deletion (such as a hash of the email), which conflicts
--    with the "delete everything" promise unless the privacy policy says so.
--  - A new account can still be created with a different Google account.
--  - Nothing in RLS or the other RPCs checks access yet, so old app builds that never
--    call get_access stay free; only min_supported_build can force them to update.

-- ── 1. app_config ────────────────────────────────────────────────────────────
create table if not exists public.app_config (
  id                  boolean primary key default true check (id),  -- exactly one row
  min_supported_build int     not null default 0,
  latest_build        int     not null default 0,
  update_url          text check (update_url is null or update_url like 'https://%'),
  paywall_enabled     boolean not null default false,
  trial_days          int     not null default 30 check (trial_days >= 0),
  -- Profiles created before this moment count as grandfathered (see header).
  grandfather_before  timestamptz,
  -- A minimum build with nowhere to update would strand people on a dead-end screen.
  check (min_supported_build = 0 or update_url is not null)
);
insert into public.app_config (id) values (true) on conflict do nothing;

-- Nobody reads or writes this table directly; get_app_config() is the only way in.
alter table public.app_config enable row level security;
revoke all on public.app_config from anon, authenticated;

-- Callable before sign-in, so the "please update" check works on the login screen too.
create or replace function public.get_app_config()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'min_supported_build', min_supported_build,
    'latest_build',        latest_build,
    'update_url',          update_url,
    'paywall_enabled',     paywall_enabled,
    'trial_days',          trial_days)
  from public.app_config limit 1;
$$;
revoke all on function public.get_app_config() from public;
grant execute on function public.get_app_config() to anon, authenticated;

-- ── 2. Grandfathering (once: only the first run backfills) ───────────────────
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'profiles' and column_name = 'grandfathered') then
    alter table public.profiles add column grandfathered boolean not null default false;
    update public.profiles set grandfathered = true;
  end if;
end $$;
-- Clients may update only username / avatar_emoji / silent_types on profiles, so
-- this column cannot be changed from the app.

-- ── 4. Premium ───────────────────────────────────────────────────────────────
alter table public.profiles add column if not exists premium_until timestamptz;

-- ── 5. The decision ──────────────────────────────────────────────────────────
create or replace function public.couple_access(p_couple uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  cfg         public.app_config;
  c           public.couples;
  trial_end   timestamptz;
  premium_end timestamptz;
begin
  select * into cfg from public.app_config limit 1;
  if cfg.id is null or not cfg.paywall_enabled then
    return jsonb_build_object('paywall_enabled', false, 'state', 'free', 'until', null);
  end if;

  select * into c from public.couples where id = p_couple;
  if not found then
    return jsonb_build_object('paywall_enabled', true, 'state', 'expired', 'until', null);
  end if;

  if exists (select 1 from public.profiles p
              where p.id in (c.user_a_id, c.user_b_id)
                and (p.grandfathered
                     or (cfg.grandfather_before is not null and p.created_at < cfg.grandfather_before))) then
    return jsonb_build_object('paywall_enabled', true, 'state', 'grandfathered', 'until', null);
  end if;

  -- Whoever pays covers the couple for as long as they are in it.
  select max(p.premium_until) into premium_end from public.profiles p where p.id in (c.user_a_id, c.user_b_id);
  if premium_end is not null and premium_end > now() then
    return jsonb_build_object('paywall_enabled', true, 'state', 'premium', 'until', premium_end);
  end if;

  select max(p.created_at) + make_interval(days => cfg.trial_days) into trial_end
    from public.profiles p where p.id in (c.user_a_id, c.user_b_id);
  if trial_end is not null and trial_end > now() then
    return jsonb_build_object('paywall_enabled', true, 'state', 'trial', 'until', trial_end);
  end if;

  return jsonb_build_object('paywall_enabled', true, 'state', 'expired',
                            'until', greatest(trial_end, premium_end));
end $$;
revoke all on function public.couple_access(uuid) from public, anon, authenticated;

create or replace function public.get_access(p_couple uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_couple_member(p_couple) then raise exception 'Not a member'; end if;
  return public.couple_access(p_couple);
end $$;
revoke all on function public.get_access(uuid) from public, anon;
grant execute on function public.get_access(uuid) to authenticated;
