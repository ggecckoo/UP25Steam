// Hesap silme — giriş yapmış kullanıcının kendi Auth + profil verisini siler
// verify_jwt = true (Authorization zorunlu)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors() });
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey) {
      return json({ error_code: "server_config" }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error_code: "auth_required" }, 401);
    }

    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) {
      return json({ error_code: "invalid_session" }, 401);
    }

    const userId = userData.user.id;
    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // profiles + game_results: ON DELETE CASCADE
    const { error: delErr } = await admin.auth.admin.deleteUser(userId);
    if (delErr) throw delErr;

    return json({ ok: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("delete-account error:", message);
    return json({ error_code: "internal" }, 500);
  }
});

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(), "Content-Type": "application/json" },
  });
}
