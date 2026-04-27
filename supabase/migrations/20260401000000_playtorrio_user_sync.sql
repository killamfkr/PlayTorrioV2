-- PlayTorrio: per-user watch progress and settings (replaces Nuvio sync).
-- Run in your Supabase project: SQL Editor → New query → paste → Run.
-- Or: supabase db push (if using Supabase CLI).

-- Watch history: one row per user, JSON array of entries (same shape as local watch_history).
create table if not exists public.user_watch_history (
  user_id uuid primary key references auth.users (id) on delete cascade,
  entries jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

-- App settings: one row per user, JSON object of SharedPreferences (subset from client).
create table if not exists public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  prefs jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.user_watch_history enable row level security;
alter table public.user_settings enable row level security;

create policy "Users read own watch history"
  on public.user_watch_history for select
  using (auth.uid() = user_id);

create policy "Users insert own watch history"
  on public.user_watch_history for insert
  with check (auth.uid() = user_id);

create policy "Users update own watch history"
  on public.user_watch_history for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users read own settings"
  on public.user_settings for select
  using (auth.uid() = user_id);

create policy "Users insert own settings"
  on public.user_settings for insert
  with check (auth.uid() = user_id);

create policy "Users update own settings"
  on public.user_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- PostgREST `resolution=merge-duplicates` needs a unique constraint on the conflict key.
-- Primary key on user_id is sufficient for upsert by `user_id`.

-- Optional: keep updated_at fresh on write.
create or replace function public.playtorrio_touch_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_user_watch_history_updated on public.user_watch_history;
create trigger trg_user_watch_history_updated
  before update on public.user_watch_history
  for each row execute function public.playtorrio_touch_updated_at();

drop trigger if exists trg_user_settings_updated on public.user_settings;
create trigger trg_user_settings_updated
  before update on public.user_settings
  for each row execute function public.playtorrio_touch_updated_at();
