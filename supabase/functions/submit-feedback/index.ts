import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { audit, jsonResponse, preflight, serviceClient } from "../_shared/account.ts";

serve(async (req) => {
  const preflightResponse = preflight(req);
  if (preflightResponse) return preflightResponse;
  if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  const target = Deno.env.get("FEEDBACK_FORWARD_ENDPOINT") ?? "";
  if (!target) return jsonResponse(503, { error: "feedback_forward_not_configured" });

  const payload = await req.text();
  const response = await fetch(target, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: payload,
  });
  if (!response.ok) {
    return jsonResponse(502, {
      error: "feedback_forward_failed",
      status: response.status,
    });
  }

  try {
    await audit(serviceClient(), "feedback_submit", null, "ok");
  } catch (_) {
    // Feedback forwarding should not fail just because audit is unavailable.
  }
  return jsonResponse(202, { ok: true });
});
