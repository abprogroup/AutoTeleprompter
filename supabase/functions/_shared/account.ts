import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function jsonResponse(
  status: number,
  body: unknown,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function preflight(req: Request): Response | null {
  return req.method === "OPTIONS" ? new Response("ok", { headers: corsHeaders }) : null;
}

export function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) {
    throw new Error("missing_server_configuration");
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function requireUser(req: Request) {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return { error: jsonResponse(401, { error: "missing_authorization" }) };
  }
  const client = serviceClient();
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) {
    return { error: jsonResponse(401, { error: "invalid_authorization" }) };
  }
  return { client, user: data.user, token };
}

export async function ensureActiveProfile(client: ReturnType<typeof serviceClient>, user: { id: string; email?: string }) {
  const email = user.email ?? "";
  await client.from("profiles").upsert({
    user_id: user.id,
    email,
    status: "active",
  }, { onConflict: "user_id" });

  await client.from("entitlements").upsert({
    user_id: user.id,
    role: "free",
    source: "default",
  }, { onConflict: "user_id", ignoreDuplicates: true });
}

export async function accountSnapshot(client: ReturnType<typeof serviceClient>, userId: string) {
  const [{ data: profile }, { data: entitlement }] = await Promise.all([
    client.from("profiles").select("user_id,email,display_name,status,updated_at").eq("user_id", userId).maybeSingle(),
    client.from("entitlements").select("role,source,expires_at,revoked_at,updated_at").eq("user_id", userId).maybeSingle(),
  ]);
  return {
    profile,
    entitlement: entitlement ?? { role: "free", source: "default" },
    serverTime: new Date().toISOString(),
  };
}

export async function audit(
  client: ReturnType<typeof serviceClient>,
  eventType: string,
  userId: string | null,
  status = "ok",
  metadata: Record<string, JsonValue> = {},
) {
  await client.from("audit_logs").insert({
    user_id: userId,
    actor_user_id: userId,
    event_type: eventType,
    event_status: status,
    metadata,
  });
}
