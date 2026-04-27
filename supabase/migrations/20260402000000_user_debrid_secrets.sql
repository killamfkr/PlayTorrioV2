-- Debrid API keys (Real-Debrid, TorBox, AllDebrid, Premiumize, Debrid-Link) per user.
-- Run after `20260401000000_playtorrio_user_sync.sql` (creates `playtorrio_touch_updated_at`).
-- Stored as JSON: only present keys with non-empty values. RLS: row owner only.
-- **Security:** the anon key in the app can only read/write rows for the signed-in user;
-- consider enabling Supabase "Vault" or column-level encryption in production for extra protection.

create table if not exists public.user_debrid_secrets (
  user_id uuid primary key references auth.users (id) on delete cascade,
  secrets jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.user_debrid_secrets enable row level security;

create policy "Users read own debrid secrets"
  on public.user_debrid_secrets for select
  using (auth.uid() = user_id);

create policy "Users insert own debrid secrets"
  on public.user_debrid_secrets for insert
  with check (auth.uid() = user_id);

create policy "Users update own debrid secrets"
  on public.user_debrid_secrets for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists trg_user_debrid_secrets_updated on public.user_debrid_secrets;
create trigger trg_user_debrid_secrets_updated
  before update on public.user_debrid_secrets
  for each row execute function public.playtorrio_touch_updated_at();
