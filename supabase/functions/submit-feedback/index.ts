import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { audit, jsonResponse, preflight, serviceClient } from "../_shared/account.ts";

const MAX_FEEDBACK_BYTES = 512 * 1024;
const FORWARD_TIMEOUT_MS = 15_000;

serve(async (req) => {
  const preflightResponse = preflight(req);
  if (preflightResponse) return preflightResponse;
  if (req.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" });

  const target = (Deno.env.get("FEEDBACK_FORWARD_ENDPOINT") ?? "").trim();
  if (!target) return jsonResponse(503, { error: "feedback_forward_not_configured" });

  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_FEEDBACK_BYTES) {
    return jsonResponse(413, { error: "payload_too_large" });
  }

  const rawBytes = new Uint8Array(await req.arrayBuffer());
  if (rawBytes.byteLength === 0) {
    return jsonResponse(400, { error: "empty_feedback_payload" });
  }
  if (rawBytes.byteLength > MAX_FEEDBACK_BYTES) {
    return jsonResponse(413, { error: "payload_too_large" });
  }

  const payloadText = new TextDecoder().decode(rawBytes);
  let parsed: Record<string, unknown>;
  try {
    const decoded = JSON.parse(payloadText);
    if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
      return jsonResponse(400, { error: "invalid_feedback_payload" });
    }
    parsed = decoded as Record<string, unknown>;
  } catch {
    return jsonResponse(400, { error: "invalid_feedback_json" });
  }

  const reportId = typeof parsed.reportId === "string" ? parsed.reportId.trim() : "";
  const appVersion = typeof parsed.appVersion === "string" ? parsed.appVersion.trim() : "";
  const platform = typeof parsed.platform === "string" ? parsed.platform.trim() : "";
  if (!reportId || !appVersion || !platform || reportId.length > 120) {
    return jsonResponse(400, { error: "invalid_feedback_schema" });
  }

  let response: Response;
  try {
    response = await fetch(target, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-AutoTeleprompter-Report-Id": reportId,
      },
      body: payloadText,
      signal: AbortSignal.timeout(FORWARD_TIMEOUT_MS),
    });
  } catch {
    return jsonResponse(504, { error: "feedback_forward_timeout" });
  }

  if (!response.ok) {
    return jsonResponse(502, {
      error: "feedback_forward_failed",
      status: response.status,
    });
  }

  try {
    await audit(serviceClient(), "feedback_submit", null, "ok", {
      platform,
      appVersion,
    });
  } catch (_) {
    // Feedback forwarding should not fail just because audit is unavailable.
  }
  return jsonResponse(202, { ok: true });
});
