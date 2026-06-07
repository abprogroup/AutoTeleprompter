create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text,
  status text not null default 'active'
    check (status in ('active', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create table if not exists public.entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'free'
    check (role in ('free', 'pro', 'admin')),
  source text not null default 'backend',
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.entitlements enable row level security;

create table if not exists public.license_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  code_type text not null default 'pro'
    check (code_type in ('pro', 'admin', 'trial')),
  max_uses integer not null default 1 check (max_uses > 0),
  used_count integer not null default 0 check (used_count >= 0),
  expires_at timestamptz,
  revoked_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.license_codes enable row level security;

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  platform text not null default 'windows',
  friendly_name text,
  last_seen_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, device_id)
);

alter table public.devices enable row level security;

create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  session_hash text,
  last_seen_server_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, device_id)
);

alter table public.sessions enable row level security;

create table if not exists public.audit_logs (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  event_status text not null default 'ok'
    check (event_status in ('ok', 'failed')),
  ip_address inet,
  user_agent text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.audit_logs enable row level security;

create table if not exists public.trial_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'not_started'
    check (status in ('not_started', 'active', 'expired', 'cancelled')),
  started_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.trial_state enable row level security;

create index if not exists idx_profiles_email on public.profiles (lower(email));
create index if not exists idx_entitlements_role on public.entitlements (role);
create index if not exists idx_entitlements_expiry on public.entitlements (expires_at);
create index if not exists idx_license_codes_expiry on public.license_codes (expires_at);
create index if not exists idx_license_codes_revoked on public.license_codes (revoked_at);
create index if not exists idx_devices_user_device on public.devices (user_id, device_id);
create index if not exists idx_devices_revoked on public.devices (revoked_at);
create index if not exists idx_sessions_user_device on public.sessions (user_id, device_id);
create index if not exists idx_sessions_expiry on public.sessions (expires_at);
create index if not exists idx_sessions_revoked on public.sessions (revoked_at);
create index if not exists idx_audit_logs_user_created on public.audit_logs (user_id, created_at desc);
create index if not exists idx_audit_logs_event_created on public.audit_logs (event_type, created_at desc);

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists entitlements_select_own on public.entitlements;
create policy entitlements_select_own
  on public.entitlements
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists devices_select_own on public.devices;
create policy devices_select_own
  on public.devices
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists sessions_select_own on public.sessions;
create policy sessions_select_own
  on public.sessions
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists audit_logs_select_own on public.audit_logs;
create policy audit_logs_select_own
  on public.audit_logs
  for select
  to authenticated
  using (auth.uid() = user_id or auth.uid() = actor_user_id);

drop policy if exists trial_state_select_own on public.trial_state;
create policy trial_state_select_own
  on public.trial_state
  for select
  to authenticated
  using (auth.uid() = user_id);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists entitlements_touch_updated_at on public.entitlements;
create trigger entitlements_touch_updated_at
  before update on public.entitlements
  for each row execute function public.touch_updated_at();

drop trigger if exists devices_touch_updated_at on public.devices;
create trigger devices_touch_updated_at
  before update on public.devices
  for each row execute function public.touch_updated_at();

drop trigger if exists sessions_touch_updated_at on public.sessions;
create trigger sessions_touch_updated_at
  before update on public.sessions
  for each row execute function public.touch_updated_at();

drop trigger if exists trial_state_touch_updated_at on public.trial_state;
create trigger trial_state_touch_updated_at
  before update on public.trial_state
  for each row execute function public.touch_updated_at();
