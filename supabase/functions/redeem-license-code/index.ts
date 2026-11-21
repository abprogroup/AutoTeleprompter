import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { audit, ensureActiveProfile, jsonResponse, preflight, requireUser } from "../_shared/account.ts";

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

  await ensureActiveProfile(auth.client, auth.user);
  const codeHash = await sha256Hex(code);
  const { data, error } = await auth.client.rpc("redeem_license_code_atomic", {
    p_user_id: auth.user.id,
    p_code_hash: codeHash,
  });

  if (error) {
    await audit(auth.client, "license_redeem", auth.user.id, "failed", { reason: "rpc_error" });
    return jsonResponse(500, { error: "license_redeem_failed" });
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row || row.error_code) {
    const errorCode = row?.error_code ?? "invalid_license_code";
    await audit(auth.client, "license_redeem", auth.user.id, "failed", { reason: errorCode });
    return jsonResponse(403, { error: errorCode });
  }

  const role = row.granted_role ?? "pro";
  await audit(auth.client, "license_redeem", auth.user.id, "ok", { role });
  return jsonResponse(200, {
    ok: true,
    role,
    expires_at: row.entitlement_expires_at ?? null,
  });
});
