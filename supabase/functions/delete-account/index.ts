import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { audit, jsonResponse, preflight, requireUser } from "../_shared/account.ts";

serve(async (req) => {
  const preflightResponse = preflight(req);
  if (preflightResponse) return preflightResponse;
  if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  const auth = await requireUser(req);
  if ("error" in auth) return auth.error;

  const body = await req.json().catch(() => ({}));
  const confirmation = typeof body.confirmation === "string"
    ? body.confirmation.trim()
    : "";
  const email = (auth.user.email ?? "").trim();
  const confirmed = confirmation === "DELETE" ||
    (email.length > 0 && confirmation.toLowerCase() === email.toLowerCase());

  if (!confirmed) {
    await audit(auth.client, "account_delete", auth.user.id, "failed", {
      reason: "confirmation_mismatch",
    });
    return jsonResponse(400, { error: "confirmation_mismatch" });
  }

  const userId = auth.user.id;

  // Scrub PII from existing audit logs for this user before removing rows.
  const { error: scrubError } = await auth.client.rpc("scrub_user_audit_pii", {
    p_user_id: userId,
  });
  if (scrubError) {
    return jsonResponse(500, { error: "audit_scrub_failed" });
  }

  for (const table of ["trial_state", "sessions", "devices", "entitlements", "profiles"]) {
    const { error } = await auth.client.from(table).delete().eq("user_id", userId);
    if (error) {
      return jsonResponse(500, { error: "cleanup_failed", table });
    }
  }

  const { error } = await auth.client.auth.admin.deleteUser(userId);
  if (error) {
    return jsonResponse(500, { error: "auth_delete_failed" });
  }

  // Record anonymized deletion event with zero PII.
  try {
    await audit(auth.client, "account_delete", null, "ok", { deleted: true });
  } catch (_) {
    // Account deletion already succeeded; do not fail response if audit fails.
  }

  return jsonResponse(200, { ok: true });
});
