grant usage on schema public to authenticated, service_role;

grant select on table
  public.profiles,
  public.entitlements,
  public.devices,
  public.sessions,
  public.audit_logs,
  public.trial_state
to authenticated;

grant all privileges on table
  public.profiles,
  public.entitlements,
  public.license_codes,
  public.devices,
  public.sessions,
  public.audit_logs,
  public.trial_state
to service_role;

grant usage, select on sequence public.audit_logs_id_seq to service_role;
