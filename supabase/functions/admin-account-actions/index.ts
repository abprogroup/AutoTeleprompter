import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { accountSnapshot, audit, jsonResponse, preflight, requireUser } from "../_shared/account.ts";

serve(async (req) => {
  const preflightResponse = preflight(req);
  if (preflightResponse) return preflightResponse;
  if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  const auth = await requireUser(req);
  if ("error" in auth) return auth.error;
  const snapshot = await accountSnapshot(auth.client, auth.user.id);
  if (!snapshot.entitlement?.is_admin) {
    await audit(auth.client, "admin_action", auth.user.id, "failed", { reason: "not_admin" });
    return jsonResponse(403, { error: "admin_required" });
  }

  await audit(auth.client, "admin_action_stub", auth.user.id);
  return jsonResponse(501, {
    error: "admin_actions_not_implemented",
    message: "Use Supabase Studio plus audited Edge Functions until the v6 admin dashboard is scoped.",
  });
});
