// Runs the repo's migrations on PGlite (Postgres in WebAssembly) with a
// stand-in for Supabase's auth schema and roles, then checks the
// multiplayer tables: the versioned commit, hands, results, and who can
// read what under RLS. No Docker or Postgres needed:
//
//   mkdir -p /tmp/pglite && cd /tmp/pglite && npm i @electric-sql/pglite@0.2.17
//   node <repo>/supabase/tests/multiplayer_sql_check.mjs
//
// (PGlite is looked up from the directory it is run in.)
import { readFileSync, readdirSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS = join(here, "..", "migrations");
const require = createRequire(join(process.cwd(), "noop.js"));
const { PGlite } = await import(pathToFileURL(require.resolve("@electric-sql/pglite")).href);
const db = new PGlite();

await db.exec(`
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;
  create schema auth;
  create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb default '{}'::jsonb);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema auth to anon, authenticated, service_role;
  grant execute on function auth.uid() to anon, authenticated, service_role;
  create publication supabase_realtime;
`);

for (const file of readdirSync(MIGRATIONS).sort()) {
  // PGlite has no pgcrypto; gen_random_uuid() is core Postgres anyway.
  await db.exec(readFileSync(`${MIGRATIONS}/${file}`, "utf8").replace('create extension if not exists "pgcrypto";', ""));
  console.log("applied", file);
}
await db.exec(`
  grant usage on schema public to anon, authenticated, service_role;
  -- As on Supabase: table privileges are broad and RLS does the limiting.
  grant all on all tables in schema public to anon, authenticated;
  grant all on all tables in schema public to service_role;
`);

const ids = ["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222", "33333333-3333-3333-3333-333333333333"];
for (const [i, id] of ids.entries()) {
  await db.query("insert into auth.users (id, email, raw_user_meta_data) values ($1, null, $2)", [id, JSON.stringify({ display_name: `p${i}` })]);
}
const profiles = await db.query("select id, email, display_name from public.profiles order by display_name");
assert.equal(profiles.rows.length, 3, "anonymous users get profiles");

const table = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
await db.query("insert into public.game_tables (id, code, host, seats) values ($1, 'ABC234', $2, '[]')", [table, ids[0]]);
await db.query("insert into public.game_table_members (table_id, user_id, seat, display_name, preset) values ($1, $2, 0, 'p0', 'kok'), ($1, $3, 1, 'p1', 'sis')", [table, ids[0], ids[1]]);
await assert.rejects(
  db.query("insert into public.game_table_members (table_id, user_id, seat) values ($1, $2, 0)", [table, ids[2]]),
  /duplicate key/,
  "two people in one seat",
);

const commit = (expected, hands, results = []) =>
  db.query(
    "select public.game_table_commit($1, $2, 'playing', '[]'::jsonb, $3::jsonb, now(), $4::jsonb, $5::jsonb, $6::jsonb) as v",
    [table, expected, JSON.stringify({ phase: "playing", seq: expected }), JSON.stringify({ secret: [1, 2, 3] }), JSON.stringify(hands), JSON.stringify(results)],
  );

let v = (await commit(0, [{ user_id: ids[0], seat: 0, cards: [{ id: 1 }] }, { user_id: ids[1], seat: 1, cards: [{ id: 2 }] }])).rows[0].v;
assert.equal(v, 1);
assert.equal((await commit(0, [])).rows[0].v, -1, "a stale version is refused");
v = (await commit(1, [{ user_id: ids[0], seat: 0, cards: [{ id: 7 }] }], [{ user_id: ids[0], score: 5, placement: 1, won: true }, { user_id: ids[1], score: 40, placement: 2, won: false }])).rows[0].v;
assert.equal(v, 2);
const hand0 = await db.query("select cards from public.game_table_hands where user_id = $1", [ids[0]]);
assert.deepEqual(hand0.rows[0].cards, [{ id: 7 }]);
const prof = await db.query("select display_name, games_played, games_won from public.profiles order by display_name");
assert.deepEqual(prof.rows.map((r) => [r.display_name, r.games_played, r.games_won]), [["p0", 1, 1], ["p1", 1, 0], ["p2", 0, 0]]);
assert.equal((await db.query("select count(*)::int as n from public.game_results")).rows[0].n, 2);

// Reading as each player, under RLS.
async function as(user, sql, params = []) {
  await db.exec("set role authenticated");
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [user]);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec("reset role");
  }
}
assert.equal((await as(ids[0], "select id from public.game_tables")).length, 1, "a member sees the table");
assert.equal((await as(ids[2], "select id from public.game_tables")).length, 0, "a stranger does not");
assert.equal((await as(ids[1], "select user_id from public.game_table_members")).length, 2, "members see who sits where");
assert.equal((await as(ids[2], "select user_id from public.game_table_members")).length, 0);
const ownHands = await as(ids[1], "select user_id, cards from public.game_table_hands");
assert.deepEqual(ownHands.map((r) => r.user_id), [ids[1]], "each sees only their own hand");
assert.equal((await as(ids[0], "select * from public.game_table_engines")).length, 0, "no client reads the engine");
const updated = await as(ids[0], "update public.game_tables set status = 'over' returning id");
assert.equal(updated.length, 0, "clients cannot write the table");
assert.equal((await as(ids[0], "update public.game_table_hands set cards = '[]' returning user_id")).length, 0, "nor their hand");
assert.equal((await as(ids[0], "delete from public.game_table_members returning user_id")).length, 0, "nor the seats");
await assert.rejects(
  as(ids[2], "insert into public.game_table_members (table_id, user_id, seat) values ($1, $2, 2)", [table, ids[2]]),
  /row-level security/,
  "nor sit down by themselves",
);
await assert.rejects(
  as(ids[0], "select public.game_table_commit($1, 2, 'over', null, '{}'::jsonb, null, null, '[]'::jsonb, '[]'::jsonb)", [table]),
  /permission denied/,
  "clients cannot commit",
);
const pub = await db.query("select tablename from pg_publication_tables where pubname = 'supabase_realtime' order by tablename");
assert.deepEqual(pub.rows.map((r) => r.tablename), ["game_table_hands", "game_table_members", "game_tables"]);
console.log("SQL OK");
