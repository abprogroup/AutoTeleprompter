alter table public.entitlements
  add column if not exists status text not null default 'active'
    check (status in ('active', 'expired', 'revoked')),
  add column if not exists current_period_end timestamptz;

update public.entitlements
set current_period_end = expires_at
where current_period_end is null
  and expires_at is not null;

update public.entitlements
set status = case
  when revoked_at is not null then 'revoked'
  when role <> 'admin'
    and coalesce(current_period_end, expires_at) is not null
    and coalesce(current_period_end, expires_at) <= now() then 'expired'
  else 'active'
end;

create index if not exists idx_entitlements_status
  on public.entitlements (status);

create index if not exists idx_entitlements_current_period_end
  on public.entitlements (current_period_end);
