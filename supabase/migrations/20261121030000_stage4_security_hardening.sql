-- Stage 4 security hardening:
-- 1. Atomic license redemption with row-level lock (prevents double-redemption
--    races), disabled-profile rejection, and bounded trial expiry.
-- 2. GDPR audit log PII scrubber for account deletion.

create or replace function public.redeem_license_code_atomic(
  p_user_id uuid,
  p_code_hash text
)
returns table (
  error_code text,
  granted_role text,
  entitlement_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_status text;
  v_license public.license_codes%rowtype;
  v_role text;
  v_expiry timestamptz;
begin
  select status
    into v_profile_status
    from public.profiles
   where user_id = p_user_id;

  if v_profile_status = 'disabled' then
    return query select 'account_disabled'::text, null::text, null::timestamptz;
    return;
  end if;

  select *
    into v_license
    from public.license_codes
   where code_hash = p_code_hash
   for update;

  if not found or v_license.revoked_at is not null then
    return query select 'invalid_license_code'::text, null::text, null::timestamptz;
    return;
  end if;

  if v_license.expires_at is not null and v_license.expires_at <= now() then
    return query select 'expired_license_code'::text, null::text, null::timestamptz;
    return;
  end if;

  if v_license.used_count >= v_license.max_uses then
    return query select 'reused_license_code'::text, null::text, null::timestamptz;
    return;
  end if;

  v_role := case
    when v_license.code_type = 'admin' then 'admin'
    else 'pro'
  end;

  if v_license.code_type = 'trial' then
    v_expiry := coalesce(v_license.expires_at, now() + interval '14 days');
    insert into public.trial_state (user_id, status, started_at, ends_at)
    values (p_user_id, 'active', now(), v_expiry)
    on conflict (user_id) do update
      set status = 'active',
          started_at = coalesce(public.trial_state.started_at, now()),
          ends_at = excluded.ends_at;
  else
    v_expiry := null;
  end if;

  update public.license_codes
     set used_count = used_count + 1
   where id = v_license.id;

  insert into public.entitlements (
    user_id,
    role,
    status,
    source,
    current_period_end,
    expires_at,
    revoked_at
  )
  values (
    p_user_id,
    v_role,
    'active',
    case when v_license.code_type = 'trial' then 'trial_code' else 'license_code' end,
    v_expiry,
    v_expiry,
    null
  )
  on conflict (user_id) do update
    set role = excluded.role,
        status = 'active',
        source = excluded.source,
        current_period_end = excluded.current_period_end,
        expires_at = excluded.expires_at,
        revoked_at = null;

  return query select null::text, v_role, v_expiry;
end;
$$;

create or replace function public.scrub_user_audit_pii(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.audit_logs
     set user_id = null,
         actor_user_id = null,
         ip_address = null,
         user_agent = null,
         metadata = coalesce(metadata, '{}'::jsonb) - 'email' - 'ip' - 'deviceId'
   where user_id = p_user_id
      or actor_user_id = p_user_id;
end;
$$;

revoke all on function public.redeem_license_code_atomic(uuid, text) from public, anon, authenticated;
grant execute on function public.redeem_license_code_atomic(uuid, text) to service_role;

revoke all on function public.scrub_user_audit_pii(uuid) from public, anon, authenticated;
grant execute on function public.scrub_user_audit_pii(uuid) to service_role;
