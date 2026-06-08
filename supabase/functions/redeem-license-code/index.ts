import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { audit, jsonResponse, preflight, requireUser } from "../_shared/account.ts";

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

serve(async (req) => {
  const preflightResponse = preflight(req);
  if (preflightResponse) return preflightResponse;
  if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  const auth = await requireUser(req);
  if ("error" in auth) return auth.error;
  const body = await req.json().catch(() => ({}));
  const code = typeof body.code === "string" ? body.code.trim() : "";
  if (!code) return jsonResponse(400, { error: "missing_license_code" });

  const codeHash = await sha256Hex(code);
  const { data: license } = await auth.client.from("license_codes")
    .select("id,code_type,max_uses,used_count,expires_at,revoked_at")
    .eq("code_hash", codeHash)
    .maybeSingle();

  if (!license || license.revoked_at) {
    await audit(auth.client, "license_redeem", auth.user.id, "failed", { reason: "invalid_or_revoked" });
    return jsonResponse(403, { error: "invalid_license_code" });
  }
  if (license.expires_at && new Date(license.expires_at).getTime() < Date.now()) {
    await audit(auth.client, "license_redeem", auth.user.id, "failed", { reason: "expired" });
    return jsonResponse(403, { error: "expired_license_code" });
  }
  if (license.used_count >= license.max_uses) {
    await audit(auth.client, "license_redeem", auth.user.id, "failed", { reason: "used" });
    return jsonResponse(403, { error: "reused_license_code" });
  }

  const role = license.code_type === "admin" ? "admin" : "pro";
  await auth.client.from("entitlements").upsert({
    user_id: auth.user.id,
    role,
    status: "active",
    source: "license_code",
    current_period_end: null,
    expires_at: null,
    revoked_at: null,
  }, { onConflict: "user_id" });
  await auth.client.from("license_codes").update({
    used_count: license.used_count + 1,
  }).eq("id", license.id);
  await audit(auth.client, "license_redeem", auth.user.id, "ok", { role });
  return jsonResponse(200, { ok: true, role });
});
