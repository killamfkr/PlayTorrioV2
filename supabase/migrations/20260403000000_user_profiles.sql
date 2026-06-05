-- Up to 4 viewing profiles per auth user (Nuvio-style). Back up watch history,
-- settings, debrid per (user_id, profile_id) where profile_id = 1..4.
-- Run in SQL Editor after previous PlayTorrio migrations.

-- 1) Watch history: composite key
alter table public.user_watch_history
  add column if not exists profile_id int not null default 1
  check (profile_id between 1 and 4);

alter table public.user_watch_history drop constraint if exists user_watch_history_pkey;
alter table public.user_watch_history
  add primary key (user_id, profile_id);

-- 2) Settings
alter table public.user_settings
  add column if not exists profile_id int not null default 1
  check (profile_id between 1 and 4);

alter table public.user_settings drop constraint if exists user_settings_pkey;
alter table public.user_settings
  add primary key (user_id, profile_id);

-- 3) Debrid secrets
alter table public.user_debrid_secrets
  add column if not exists profile_id int not null default 1
  check (profile_id between 1 and 4);

alter table public.user_debrid_secrets drop constraint if exists user_debrid_secrets_pkey;
alter table public.user_debrid_secrets
  add primary key (user_id, profile_id);

-- 4) Optional display names + avatar slot (0–7) for UI, synced across devices
create table if not exists public.user_profile_meta (
  user_id uuid not null references auth.users (id) on delete cascade,
  profile_id int not null check (profile_id between 1 and 4),
  name text,
  avatar_key int not null default 0 check (avatar_key between 0 and 7),
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_id)
);

alter table public.user_profile_meta enable row level security;

create policy "Users read own profile meta"
  on public.user_profile_meta for select
  using (auth.uid() = user_id);

create policy "Users insert own profile meta"
  on public.user_profile_meta for insert
  with check (auth.uid() = user_id);

create policy "Users update own profile meta"
  on public.user_profile_meta for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists trg_user_profile_meta_updated on public.user_profile_meta;
create trigger trg_user_profile_meta_updated
  before update on public.user_profile_meta
  for each row execute function public.playtorrio_touch_updated_at();
