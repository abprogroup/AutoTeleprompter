import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { audit, jsonResponse, preflight, requireUser } from "../_shared/account.ts";

serve(async (req) => {
  const preflightResponse = preflight(req);
  if (preflightResponse) return preflightResponse;
  if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  const auth = await requireUser(req);
  if ("error" in auth) return auth.error;
  const body = await req.json().catch(() => ({}));
  const deviceId = typeof body.deviceId === "string" ? body.deviceId.trim() : "";
  if (deviceId) {
    await auth.client.from("sessions")
      .update({ revoked_at: new Date().toISOString() })
      .eq("user_id", auth.user.id)
      .eq("device_id", deviceId);
  }
  await audit(auth.client, "session_logout", auth.user.id, "ok", { deviceId });
  return jsonResponse(200, { ok: true });
});
