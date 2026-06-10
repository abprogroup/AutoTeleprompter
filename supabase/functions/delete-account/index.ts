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
  await audit(auth.client, "account_delete", userId, "ok", { email });

  for (const table of ["trial_state", "sessions", "devices", "entitlements", "profiles"]) {
    const { error } = await auth.client.from(table).delete().eq("user_id", userId);
    if (error) {
      await audit(auth.client, "account_delete_cleanup", userId, "failed", {
        table,
        error: error.message,
      });
      return jsonResponse(500, { error: "cleanup_failed", table });
    }
  }

  const { error } = await auth.client.auth.admin.deleteUser(userId);
  if (error) {
    await audit(auth.client, "account_delete_auth", userId, "failed", {
      error: error.message,
    });
    return jsonResponse(500, { error: "auth_delete_failed" });
  }

  return jsonResponse(200, { ok: true });
});
