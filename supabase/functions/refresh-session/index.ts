import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { accountSnapshot, audit, ensureActiveProfile, jsonResponse, preflight, requireUser } from "../_shared/account.ts";

serve(async (req) => {
  const preflightResponse = preflight(req);
  if (preflightResponse) return preflightResponse;
  if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  const auth = await requireUser(req);
  if ("error" in auth) return auth.error;
  const body = await req.json().catch(() => ({}));
  const deviceId = typeof body.deviceId === "string" ? body.deviceId.trim() : "";
  if (!deviceId) return jsonResponse(400, { error: "missing_device_id" });

  await ensureActiveProfile(auth.client, auth.user);
  await auth.client.from("devices").upsert({
    user_id: auth.user.id,
    device_id: deviceId,
    platform: "windows",
    friendly_name: typeof body.friendlyName === "string" ? body.friendlyName : null,
    last_seen_at: new Date().toISOString(),
  }, { onConflict: "user_id,device_id" });

  await auth.client.from("sessions").upsert({
    user_id: auth.user.id,
    device_id: deviceId,
    last_seen_server_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString(),
  }, { onConflict: "user_id,device_id" });

  const snapshot = await accountSnapshot(auth.client, auth.user.id, { deviceId });
  if (snapshot.profile?.status === "disabled") {
    await audit(auth.client, "profile_disabled_refresh", auth.user.id, "failed", { deviceId });
    return jsonResponse(403, { error: "account_disabled" });
  }
  await audit(auth.client, "session_refresh", auth.user.id, "ok", { deviceId });
  return jsonResponse(200, { ok: true, ...snapshot });
});
