import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type JsonValue =
  | string
  | number
  | boolean
  | null
  | { [key: string]: JsonValue }
  | JsonValue[];

type EntitlementRow = {
  role?: string | null;
  status?: string | null;
  source?: string | null;
  current_period_end?: string | null;
  expires_at?: string | null;
  revoked_at?: string | null;
  updated_at?: string | null;
};

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
    status: "active",
    source: "default",
    current_period_end: null,
    expires_at: null,
    revoked_at: null,
  }, { onConflict: "user_id", ignoreDuplicates: true });
}

export async function accountSnapshot(client: ReturnType<typeof serviceClient>, userId: string) {
  const serverTime = new Date();
  const [{ data: profile }, { data: entitlement }] = await Promise.all([
    client.from("profiles").select("user_id,email,display_name,status,updated_at").eq("user_id", userId).maybeSingle(),
    client.from("entitlements").select("role,status,source,current_period_end,expires_at,revoked_at,updated_at").eq("user_id", userId).maybeSingle(),
  ]);
  const normalizedEntitlement = normalizeEntitlement(entitlement, serverTime);
  return {
    profile,
    entitlement: normalizedEntitlement,
    serverTime: serverTime.toISOString(),
  };
}

export function normalizeEntitlement(entitlement: EntitlementRow | null, serverTime: Date) {
  const role = normalizeRole(entitlement?.role);
  const status = normalizeStatus(entitlement?.status);
  const currentPeriodEnd = entitlement?.current_period_end ?? entitlement?.expires_at ?? null;
  const revokedAt = entitlement?.revoked_at ?? null;
  let effectiveStatus = status;

  if (revokedAt || status === "revoked") {
    effectiveStatus = "revoked";
  } else if (
    role !== "admin" &&
    currentPeriodEnd &&
    new Date(currentPeriodEnd).getTime() <= serverTime.getTime()
  ) {
    effectiveStatus = "expired";
  } else {
    effectiveStatus = "active";
  }

  const isAdmin = role === "admin" && effectiveStatus === "active";
  const hasPremiumAccess =
    effectiveStatus === "active" &&
    (role === "admin" || role === "pro");

  return {
    role,
    status: effectiveStatus,
    stored_status: status,
    source: entitlement?.source ?? "default",
    current_period_end: currentPeriodEnd,
    expires_at: entitlement?.expires_at ?? currentPeriodEnd,
    revoked_at: revokedAt,
    updated_at: entitlement?.updated_at ?? null,
    has_premium_access: hasPremiumAccess,
    is_admin: isAdmin,
  };
}

function normalizeRole(value: string | null | undefined) {
  const role = (value ?? "free").trim().toLowerCase();
  return role === "admin" || role === "pro" ? role : "free";
}

function normalizeStatus(value: string | null | undefined) {
  const status = (value ?? "active").trim().toLowerCase();
  if (status === "revoked" || status === "expired") return status;
  return "active";
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
