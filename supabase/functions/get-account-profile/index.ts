import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { accountSnapshot, audit, ensureActiveProfile, jsonResponse, preflight, requireUser } from "../_shared/account.ts";

serve(async (req) => {
  const preflightResponse = preflight(req);
  if (preflightResponse) return preflightResponse;
  if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  const auth = await requireUser(req);
  if ("error" in auth) return auth.error;

  await ensureActiveProfile(auth.client, auth.user);
  const snapshot = await accountSnapshot(auth.client, auth.user.id);
  if (snapshot.profile?.status === "disabled") {
    await audit(auth.client, "profile_disabled_access", auth.user.id, "failed");
    return jsonResponse(403, { error: "account_disabled" });
  }
  await audit(auth.client, "profile_read", auth.user.id);
  return jsonResponse(200, { ok: true, ...snapshot });
});
