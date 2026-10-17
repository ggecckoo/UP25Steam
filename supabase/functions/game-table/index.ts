// Masa (multiplayer table) — every move of a networked sitting goes through
// here and is checked by the same rules as the Godot client's match.gd.
// verify_jwt = true: the caller is a signed-in Supabase user.
//
// POST { action, ... }:
//   create { name?, preset? }           → { table_id, code, seat }
//   join   { code, name?, preset? }     → { table_id, seat }
//   leave  { table_id }
//   start  { table_id }                  host only; empty seats get bots
//   play   { table_id, card_id }
//   throw  { table_id, choice }          0 rock, 1 paper, 2 scissors
//   tick   { table_id }                  call once the public deadline has passed
//   state  { table_id }                  → { table, seat, hand }
//
// Players follow the table over Realtime: `game_tables` (the public state,
// RLS: members only) and their own `game_table_hands` row.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { GameError } from "../_shared/game/engine.ts";
import { TableService } from "../_shared/game/service.ts";
import { SupabaseStore } from "./store.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors() });
  }
  if (req.method !== "POST") {
    return json({ error_code: "method_not_allowed" }, 405);
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
    const user = userData.user.id;

    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const tables = new TableService(new SupabaseStore(admin), () => Date.now());

    const body = await req.json().catch(() => ({}));
    const tableId = String(body.table_id ?? "");
    switch (String(body.action ?? "")) {
      case "create": {
        const made = await tables.create(user, String(body.name ?? ""), String(body.preset ?? ""));
        return json({ table_id: made.tableId, code: made.code, seat: made.seat });
      }
      case "join": {
        const joined = await tables.join(user, String(body.code ?? ""), String(body.name ?? ""), String(body.preset ?? ""));
        return json({ table_id: joined.tableId, seat: joined.seat });
      }
      case "leave":
        await tables.leave(user, tableId);
        return json({ ok: true });
      case "start":
        await tables.start(user, tableId);
        return json({ ok: true });
      case "play":
        await tables.play(user, tableId, Number(body.card_id));
        return json({ ok: true });
      case "throw":
        await tables.throwHand(user, tableId, Number(body.choice));
        return json({ ok: true });
      case "tick":
        await tables.tick(user, tableId);
        return json({ ok: true });
      case "state": {
        const seen = await tables.state(user, tableId);
        return json({ table: seen.table, seat: seen.seat, hand: seen.hand });
      }
      default:
        return json({ error_code: "unknown_action" }, 400);
    }
  } catch (err) {
    if (err instanceof GameError) {
      return json({ error_code: err.code }, 409);
    }
    const message = err instanceof Error ? err.message : String(err);
    console.error("game-table error:", message);
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
