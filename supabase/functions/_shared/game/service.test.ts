// node --test supabase/functions/_shared/game/
// The table service end to end against the in-memory store: a lobby filled
// by code, a sitting played out by four people over the API, someone
// walking away mid-hand, two moves racing for the same table.

import { test } from "node:test";
import assert from "node:assert/strict";
import { acting, GameError, ROCK } from "./engine.ts";
import type { Card, Engine } from "./engine.ts";
import { MemoryStore } from "./memory_store.ts";
import { TableService } from "./service.ts";

function setup(seed = 1) {
  const store = new MemoryStore();
  let clock = 1_000_000;
  let state = seed;
  const random = () => {
    state = (state * 1103515245 + 12345) % 2147483648;
    return state / 2147483648;
  };
  const service = new TableService(store, () => clock, random);
  return {
    store,
    service,
    now: () => clock,
    at: (t: number) => {
      clock = Math.max(clock, t);
    },
  };
}

const code = (err: unknown) => (err instanceof GameError ? err.code : String(err));

test("a lobby fills by code, one character each, and only the host starts it", async () => {
  const { store, service } = setup();
  const made = await service.create("u0", "Ayşe", "kok");
  assert.match(made.code, /^[A-HJ-NP-Z2-9]{6}$/);
  assert.equal(made.seat, 0);
  const b = await service.join("u1", made.code.toLowerCase(), "Bora", "kok");
  assert.equal(b.seat, 1);
  assert.equal((await service.join("u1", made.code, "Bora", "kok")).seat, 1, "joining twice keeps the seat");
  await service.join("u2", made.code, "", "sis");
  await service.join("u3", made.code, "Deniz", "dere");
  await assert.rejects(service.join("u4", made.code, "Ece", "kaya"), (err) => code(err) === "table_full");
  const members = await store.members(made.tableId);
  const presets = members.map((m) => m.preset);
  assert.equal(new Set(presets).size, 4, "a character sits once per table");
  assert.equal(members.find((m) => m.userId === "u2")!.name, "Sis", "a blank name takes the character's");
  const lobby = await store.table(made.tableId);
  assert.equal(lobby!.seats.filter((s) => s.taken).length, 4);
  await assert.rejects(service.start("u1", made.tableId), (err) => code(err) === "not_host");
  await service.start("u0", made.tableId);
  assert.equal((await store.table(made.tableId))!.status, "playing");
  await assert.rejects(service.join("u5", made.code, "Fer", "kaya"), (err) => code(err) === "table_started");
});

test("bots fill the empty seats and each person sees only their own hand", async () => {
  const { store, service } = setup(2);
  const made = await service.create("u0", "Ayşe", "kaya");
  await service.join("u1", made.code, "Bora", "sis");
  await service.start("u0", made.tableId);
  const engine = (await store.engine(made.tableId))!;
  assert.deepEqual(engine.seats.map((s) => s.user), ["u0", "u1", null, null]);
  assert.equal(new Set(engine.seats.map((s) => s.preset)).size, 4);
  const seen = await service.state("u1", made.tableId);
  assert.equal(seen.seat, 1);
  assert.deepEqual(seen.hand, engine.seats[1].hand);
  assert.deepEqual(store.handOf(made.tableId, "u0"), engine.seats[0].hand);
  const state = JSON.stringify(seen.table.state);
  for (const card of engine.seats[0].hand) assert.ok(!state.includes(`"id":${card.id},`));
  await assert.rejects(service.state("stranger", made.tableId), (err) => code(err) === "not_a_member");
});

async function playOut(t: ReturnType<typeof setup>, tableId: string, users: string[]) {
  // Everyone plays their lowest card on their turn and throws in turn rock,
  // paper, scissors; when no one is due, the clock moves to the next
  // deadline and someone ticks.
  for (let step = 0; step < 20000; step++) {
    const engine = (await t.store.engine(tableId)) as Engine;
    if (engine.phase === "over") return engine;
    const turn = acting(engine);
    if (turn >= 0 && engine.seats[turn].user !== null && t.now() < engine.deadline) {
      const hand = t.store.handOf(tableId, engine.seats[turn].user!) as Card[];
      assert.deepEqual(hand, engine.seats[turn].hand, "the hand row is behind");
      await t.service.play(engine.seats[turn].user!, tableId, hand[0].id);
      continue;
    }
    const duel = engine.duel;
    if (duel && duel.stage === "choose") {
      const waiting = [duel.loser, duel.winner].filter((s) => engine.seats[s].user !== null && duel.picks[String(s)] === undefined);
      if (waiting.length > 0) {
        await t.service.throwHand(engine.seats[waiting[0]].user!, tableId, (ROCK + step) % 3);
        continue;
      }
    }
    t.at(engine.deadline);
    await t.service.tick(users[step % users.length], tableId);
  }
  throw new Error("the sitting never ended");
}

test("four people play a whole sitting through the API; results land once", async () => {
  const t = setup(3);
  const users = ["u0", "u1", "u2", "u3"];
  const made = await t.service.create("u0", "Ayşe", "kok");
  for (const u of users.slice(1)) await t.service.join(u, made.code, u, "");
  await t.service.start("u0", made.tableId);
  const engine = await playOut(t, made.tableId, users);
  const row = (await t.store.table(made.tableId))!;
  assert.equal(row.status, "over");
  assert.equal(row.deadline, null);
  assert.equal(t.store.results.length, 4, "every person's place recorded once");
  assert.deepEqual(t.store.results.map((r) => r.placement).sort(), [1, 2, 3, 4]);
  assert.equal(t.store.results.filter((r) => r.won).length, 1);
  assert.equal(t.store.results.find((r) => r.won)!.userId, engine.seats[engine.champion].user);
  // Late ticks after the end change nothing.
  const commits = t.store.commits;
  await t.service.tick("u1", made.tableId);
  assert.equal(t.store.commits, commits);
  await assert.rejects(t.service.play("u1", made.tableId, 1), (err) => code(err) === "not_playing");
});

test("someone walking away mid-hand hands their seat to a bot", async () => {
  const t = setup(4);
  const made = await t.service.create("u0", "Ayşe", "kok");
  await t.service.join("u1", made.code, "Bora", "sis");
  await t.service.start("u0", made.tableId);
  await t.service.leave("u1", made.tableId);
  const engine = (await t.store.engine(made.tableId))!;
  assert.equal(engine.seats[1].user, null);
  assert.deepEqual(t.store.handOf(made.tableId, "u1"), []);
  await assert.rejects(t.service.play("u1", made.tableId, 1), (err) => code(err) === "not_seated");
  const done = await playOut(t, made.tableId, ["u0"]);
  assert.equal(done.phase, "over");
});

test("two moves racing for the same table: the loser of the race retries", async () => {
  const t = setup(5);
  const made = await t.service.create("u0", "Ayşe", "kok");
  await t.service.join("u1", made.code, "Bora", "sis");
  await t.service.start("u0", made.tableId);
  // Run the clock to someone's turn.
  let engine = (await t.store.engine(made.tableId))!;
  while (engine.seats[acting(engine)]?.user === null || acting(engine) < 0) {
    t.at(engine.deadline);
    await t.service.tick("u0", made.tableId);
    engine = (await t.store.engine(made.tableId))!;
  }
  const seat = acting(engine);
  const user = engine.seats[seat].user!;
  let raced = false;
  t.store.beforeCommit = (change) => {
    if (raced) return;
    raced = true;
    // Someone else commits first: the version moves on under this move.
    const row = t.store.tables.get(change.tableId)!;
    row.version += 1;
  };
  await t.service.play(user, made.tableId, engine.seats[seat].hand[0].id);
  t.store.beforeCommit = null;
  const after = (await t.store.engine(made.tableId))!;
  assert.ok(raced, "a competing commit got in first");
  assert.equal(after.seats[seat].hand.length, 6, "the card was played exactly once");
});

test("the host leaving an unstarted table closes it", async () => {
  const { store, service } = setup(6);
  const made = await service.create("u0", "Ayşe", "kok");
  await service.join("u1", made.code, "Bora", "sis");
  await service.leave("u0", made.tableId);
  assert.equal((await store.table(made.tableId))!.status, "closed");
  await assert.rejects(service.join("u2", made.code, "Cem", "kaya"), (err) => code(err) === "table_not_found");
});
