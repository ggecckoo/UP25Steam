// Game Center → Supabase oturumu
// verify_jwt = false (anon istemci imza paketini gönderir)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { encodeBase64, decodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";
import { X509Certificate } from "npm:@peculiar/x509@1.12.3";
import { createVerify, X509Certificate as NodeX509 } from "node:crypto";

// Kabul edilen bundle'lar. `ALLOWED_BUNDLES` secret'ı (virgülle ayrılmış) ile
// kod değiştirmeden genişletilebilir.
const ALLOWED_BUNDLES = new Set(
  (Deno.env.get("ALLOWED_BUNDLES") ?? "com.atikolabs.UP-25,com.atikolabs.up2540")
    .split(",")
    .map((bundle) => bundle.trim())
    .filter(Boolean),
);
const MAX_SKEW_MS = 30 * 60 * 1000; // Apple örnekleri ~30 dk

type Body = {
  teamPlayerID: string;
  gamePlayerID?: string;
  displayName?: string;
  publicKeyURL: string;
  signature: string;
  salt: string;
  timestamp: number | string;
  bundleID: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors() });
  }

  try {
    const body = (await req.json()) as Body;
    if (!body.teamPlayerID || !body.publicKeyURL || !body.signature || !body.salt || !body.bundleID) {
      return json({ error_code: "missing_fields" }, 400);
    }
    if (!ALLOWED_BUNDLES.has(body.bundleID)) {
      return json({ error_code: "invalid_bundle" }, 403);
    }

    const timestamp = Number(body.timestamp);
    if (!Number.isFinite(timestamp)) {
      return json({ error_code: "invalid_timestamp" }, 400);
    }
    // Apple timestamp milisaniye cinsinden gelir
    if (Math.abs(Date.now() - timestamp) > MAX_SKEW_MS) {
      return json({ error_code: "signature_expired" }, 401);
    }

    let playerIds = uniqueNonEmpty([
      body.teamPlayerID,
      body.gamePlayerID,
    ]);

    let ok = false;
    for (const playerId of playerIds) {
      const verified = await verifyGameCenterSignature({
        playerId,
        bundleId: body.bundleID,
        timestamp: BigInt(Math.trunc(timestamp)),
        saltB64: body.salt,
        signatureB64: body.signature,
        publicKeyURL: body.publicKeyURL,
      });
      if (verified) {
        ok = true;
        break;
      }
    }
    if (!ok) {
      console.error("signature verify failed", {
        teamPlayerID: body.teamPlayerID,
        gamePlayerID: body.gamePlayerID,
        bundleID: body.bundleID,
        publicKeyURL: body.publicKeyURL,
        ts: timestamp,
      });
      return json({ error_code: "signature_invalid" }, 401);
    }

    // Hesap kimliği her zaman teamPlayerID (imza gamePlayerID ile de doğrulanmış olabilir)
    const accountPlayerId = body.teamPlayerID;

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!url || !serviceKey || !anonKey) {
      return json({ error_code: "server_config" }, 500);
    }

    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // .local bazı GoTrue kurulumlarında reddedilir — geçerli TLD kullan
    const email = `gc_${sanitize(accountPlayerId)}@gc.atikolabs.app`;
    const displayName = (body.displayName || "Oyuncu").slice(0, 40);
    const password = await stablePassword(accountPlayerId, serviceKey);

    let userId: string | null = null;
    const { data: existing } = await admin
      .from("profiles")
      .select("id")
      .eq("game_center_id", accountPlayerId)
      .maybeSingle();

    // Eski e-posta şeması ile açılmış hesapları da yakala
    const legacyEmail = `gc_${sanitize(accountPlayerId)}@gamecenter.yirmibes.local`;

    if (existing?.id) {
      userId = existing.id;
      const { error: updErr } = await admin.auth.admin.updateUserById(userId, {
        password,
        user_metadata: {
          display_name: displayName,
          game_center_id: accountPlayerId,
        },
      });
      if (updErr) throw updErr;
    } else {
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          display_name: displayName,
          game_center_id: accountPlayerId,
        },
      });
      if (createErr) {
        const listed = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
        const hit = listed.data.users.find(
          (u) => u.email === email || u.email === legacyEmail,
        );
        if (!hit) throw createErr;
        userId = hit.id;
        await admin.auth.admin.updateUserById(userId, {
          password,
          user_metadata: {
            display_name: displayName,
            game_center_id: accountPlayerId,
          },
        });
      } else {
        userId = created.user.id;
      }
    }

    const { error: profileErr } = await admin.from("profiles").upsert({
      id: userId,
      email,
      display_name: displayName,
      game_center_id: accountPlayerId,
    });
    if (profileErr) throw profileErr;

    const anon = createClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: session, error: signErr } = await anon.auth.signInWithPassword({
      email,
      password,
    });
    if (signErr || !session.session) {
      // Eski e-posta ile dene
      const legacy = await anon.auth.signInWithPassword({
        email: legacyEmail,
        password,
      });
      if (legacy.error || !legacy.data.session) {
        throw Object.assign(new Error("session_failed"), { error_code: "session_failed" });
      }
      return json({
        access_token: legacy.data.session.access_token,
        refresh_token: legacy.data.session.refresh_token,
        user_id: userId,
        display_name: displayName,
      });
    }

    return json({
      access_token: session.session.access_token,
      refresh_token: session.session.refresh_token,
      user_id: userId,
      display_name: displayName,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("gamecenter-auth error:", message);
    const code = (err && typeof err === "object" && "error_code" in err)
      ? String((err as { error_code?: string }).error_code ?? "internal")
      : "internal";
    return json({ error_code: code === "session_failed" ? "session_failed" : "internal" }, 500);
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

function sanitize(id: string) {
  return id.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64);
}

function uniqueNonEmpty(ids: Array<string | undefined>): string[] {
  const out: string[] = [];
  for (const id of ids) {
    if (!id || !id.trim()) continue;
    if (!out.includes(id)) out.push(id);
  }
  return out;
}

async function stablePassword(teamPlayerID: string, pepper: string) {
  const data = new TextEncoder().encode(`${pepper}:gc:${teamPlayerID}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return encodeBase64(new Uint8Array(digest));
}

async function verifyGameCenterSignature(opts: {
  playerId: string;
  bundleId: string;
  timestamp: bigint;
  saltB64: string;
  signatureB64: string;
  publicKeyURL: string;
}): Promise<boolean> {
  let url: URL;
  try {
    url = new URL(opts.publicKeyURL);
  } catch {
    return false;
  }
  if (!url.hostname.endsWith(".apple.com") && url.hostname !== "apple.com") {
    return false;
  }
  if (url.protocol !== "https:") return false;

  const certRes = await fetch(opts.publicKeyURL);
  if (!certRes.ok) {
    console.error("public key fetch failed", certRes.status, opts.publicKeyURL);
    return false;
  }
  const certDer = new Uint8Array(await certRes.arrayBuffer());
  const salt = decodeBase64(opts.saltB64);
  const signature = decodeBase64(opts.signatureB64);
  const payload = buildPayload(opts.playerId, opts.bundleId, opts.timestamp, salt);

  // 1) node:crypto (RSA-SHA256) — en güvenilir yol
  try {
    if (verifyWithNodeCrypto(certDer, payload, signature)) return true;
  } catch (err) {
    console.error("node verify error:", err);
  }

  // 2) WebCrypto + peculiar SPKI
  try {
    if (await verifyWithWebCrypto(certDer, payload, signature)) return true;
  } catch (err) {
    console.error("webcrypto verify error:", err);
  }

  return false;
}

function verifyWithNodeCrypto(
  certDer: Uint8Array,
  payload: Uint8Array,
  signature: Uint8Array,
): boolean {
  const cert = new NodeX509(Buffer.from(certDer));
  const verifier = createVerify("RSA-SHA256");
  verifier.update(Buffer.from(payload));
  verifier.end();
  return verifier.verify(cert.publicKey, Buffer.from(signature));
}

async function verifyWithWebCrypto(
  certDer: Uint8Array,
  payload: Uint8Array,
  signature: Uint8Array,
): Promise<boolean> {
  let spki: ArrayBuffer;
  try {
    const cert = new X509Certificate(certDer);
    spki = cert.publicKey.rawData;
  } catch {
    const fallback = extractSPKIFromCert(certDer);
    if (!fallback) return false;
    spki = fallback.buffer.slice(
      fallback.byteOffset,
      fallback.byteOffset + fallback.byteLength,
    ) as ArrayBuffer;
  }

  const key = await crypto.subtle.importKey(
    "spki",
    spki,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );

  return await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    signature,
    payload,
  );
}

function buildPayload(
  playerId: string,
  bundleId: string,
  timestamp: bigint,
  salt: Uint8Array,
): Uint8Array {
  const enc = new TextEncoder();
  const idBytes = enc.encode(playerId);
  const bundleBytes = enc.encode(bundleId);
  const ts = new Uint8Array(8);
  let value = timestamp;
  for (let i = 7; i >= 0; i--) {
    ts[i] = Number(value & 0xffn);
    value >>= 8n;
  }

  const out = new Uint8Array(
    idBytes.length + bundleBytes.length + ts.length + salt.length,
  );
  let o = 0;
  out.set(idBytes, o);
  o += idBytes.length;
  out.set(bundleBytes, o);
  o += bundleBytes.length;
  out.set(ts, o);
  o += ts.length;
  out.set(salt, o);
  return out;
}

/** Minimal DER parser — @peculiar/x509 başarısız olursa yedek. */
function extractSPKIFromCert(der: Uint8Array): Uint8Array | null {
  try {
    let i = 0;
    function expect(tag: number) {
      if (der[i] !== tag) throw new Error("tag");
      i++;
      return readLen();
    }
    function readLen() {
      let len = der[i++];
      if (len < 0x80) return len;
      const n = len & 0x7f;
      let v = 0;
      for (let k = 0; k < n; k++) v = (v << 8) | der[i++];
      return v;
    }
    function skip(tag: number) {
      const len = expect(tag);
      i += len;
    }

    expect(0x30); // Certificate
    expect(0x30); // tbsCertificate
    if (der[i] === 0xa0) skip(0xa0);
    skip(0x02); // serial
    skip(0x30); // signature alg
    skip(0x30); // issuer
    skip(0x30); // validity
    skip(0x30); // subject
    const spkiStart = i;
    const spkiLen = expect(0x30);
    const spkiHeaderLen = i - spkiStart;
    return der.slice(spkiStart, spkiStart + spkiHeaderLen + spkiLen);
  } catch {
    return null;
  }
}
