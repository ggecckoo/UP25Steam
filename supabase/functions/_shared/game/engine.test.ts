// node --test supabase/functions/_shared/game/
// The networked rules against the Godot client's (tests/check.gd), then
// whole sittings driven by the clock alone.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  acting,
  advance,
  beats,
  cardCount,
  createEngine,
  draws,
  GameError,
  handValue,
  makeStandings,
  OUTCOME_CAP,
  OUTCOME_EXACT,
  OUTCOME_OVER,
  OUTCOME_UNDER,
  order,
  outcomeFor,
  PAPER,
  pick,
  play,
  publicView,
  ROCK,
  SCISSORS,
  seated,
  targetFor,
  throwHand,
  TIMING,
} from "./engine.ts";
import type { Card, Engine, SeatSpec } from "./engine.ts";

const people = (n: number): SeatSpec[] =>
  ["kaya", "sis", "kok", "karaca"].map((preset, i) => ({ name: preset, preset, user: i < n ? `u${i}` : null }));

const card = (id: number, rank: number, suit = 0): Card => ({ id, rank, suit });

test("card values, outcomes, draws and throws match match.gd", () => {
  assert.equal(handValue([card(1, 12), card(2, 0, 1)]), 21);
  assert.equal(outcomeFor(80), OUTCOME_CAP);
  assert.equal(outcomeFor(31), OUTCOME_OVER);
  assert.equal(outcomeFor(30), OUTCOME_EXACT);
  assert.equal(outcomeFor(29), OUTCOME_UNDER);
  assert.deepEqual(draws(OUTCOME_OVER, 2, [0, 1, 2, 3]), [0, 0, 0, 0]);
  assert.deepEqual(draws(OUTCOME_UNDER, 2, [0, 1, 2, 3]), [0, 0, 1, 0]);
  assert.deepEqual(draws(OUTCOME_EXACT, 2, [0, 1, 2, 3]), [1, 1, 0, 1]);
  assert.deepEqual(draws(OUTCOME_EXACT, 2, [0, 2, 3]), [1, 0, 0, 1]);
  assert.deepEqual(draws(OUTCOME_CAP, 0, [0, 3]), [0, 0, 0, 1]);
  assert.deepEqual(targetFor(4), [30, 80]);
  assert.deepEqual(targetFor(3), [23, 60]);
  assert.deepEqual(targetFor(2), [14, 40]);
  assert.deepEqual(targetFor(1), [14, 40]);
  assert.deepEqual(targetFor(0), [30, 80]);
  assert.equal(outcomeFor(23, 23, 60), OUTCOME_EXACT);
  assert.equal(outcomeFor(60, 23, 60), OUTCOME_CAP);
  assert.equal(outcomeFor(24, 23, 60), OUTCOME_OVER);
  assert.equal(outcomeFor(30, 14, 40), OUTCOME_OVER);
  assert.ok(beats(ROCK, SCISSORS) && beats(SCISSORS, PAPER) && beats(PAPER, ROCK));
  for (let a = 0; a < 3; a++) assert.ok(!beats(a, a));
});

test("a deal: 28 cards, seven each, sorted, a seated holder", () => {
  const e = createEngine(people(4), 9, 0);
  assert.equal(cardCount(e), 28);
  for (const seat of e.seats) {
    assert.equal(seat.hand.length, 7);
    const values = seat.hand.map((c) => handValue([c]));
    assert.deepEqual(values, [...values].sort((a, b) => a - b));
  }
  assert.ok(seated(e).includes(e.holder));
  assert.equal(acting(e), e.holder);
  assert.equal(e.deadline, TIMING.deal + TIMING.turn);
});

test("the AI's pick: holder plays high, forced and free highs", () => {
  const e = createEngine(people(0), 1, 0);
  const low = card(901, 0);
  const high = card(902, 12, 1);
  e.seats[0].hand = [low, high];
  e.holder = 0;
  assert.equal(pick(e, 0).rank, 12);
  e.holder = 1;
  e.table = [{ by: 1, card: card(903, 12) }, { by: 2, card: card(904, 10) }];
  assert.equal(pick(e, 0).rank, 12, "a total already past the limit");
});

test("moves out of turn, of cards not held, or out of phase are refused", () => {
  const e = createEngine(people(4), 3, 0);
  const seat = acting(e);
  const other = (seat + 1) % 4;
  assert.throws(() => play(e, other, e.seats[other].hand[0].id, 0), (err: unknown) => err instanceof GameError && err.code === "not_your_turn");
  assert.throws(() => play(e, seat, 99999, 0), (err: unknown) => err instanceof GameError && err.code === "card_not_in_hand");
  assert.throws(() => throwHand(e, seat, ROCK, 0), (err: unknown) => err instanceof GameError && err.code === "no_duel");
  play(e, seat, e.seats[seat].hand[0].id, 0);
  assert.equal(e.table.length, 1);
  assert.equal(acting(e), order(e)[1]);
});

test("the public view shows no hand and no face-down card", () => {
  const e = createEngine(people(4), 5, 0);
  const seat = acting(e);
  const thrown = e.seats[seat].hand[3];
  play(e, seat, thrown.id, 0);
  const seen = JSON.stringify(publicView(e));
  for (const s of e.seats) {
    for (const c of s.hand) assert.ok(!seen.includes(`"id":${c.id},`), "a card in hand leaked");
  }
  assert.ok(!seen.includes(`"id":${thrown.id},`), "a face-down card leaked");
  assert.deepEqual((publicView(e).table as unknown[])[0], { by: seat });
});

// A call, so the type checker does not assume the phase stays put
// across advance().
const over = (e: Engine): boolean => e.phase === "over";

function invariants(e: Engine): void {
  assert.equal(cardCount(e), 28, "cards come and go");
  const ids = new Set<number>();
  for (const s of e.seats) for (const c of s.hand) ids.add(c.id);
  for (const p of e.table) ids.add(p.card.id);
  for (const c of e.middle) ids.add(c.id);
  assert.equal(ids.size, 28, "a card twice");
  // (During a throw the holder may be the one who just lost and left; the
  // next deal picks a new one.)
  if (e.phase === "playing" || e.phase === "reveal") assert.ok(!e.seats[e.holder].out, "holder left the table");
  const turn = acting(e);
  if (turn >= 0) assert.ok(!e.seats[turn].out, "an empty seat to play");
  for (const s of e.seats) if (s.out) assert.equal(s.hand.length, 0);
}

test("sittings left to the clock alone always end, cards intact", () => {
  // Four people who never act: every turn and throw times out and is
  // played for them, so this is the whole game on the server's clock.
  let hands = 0;
  for (let seed = 1; seed <= 300; seed++) {
    const e = createEngine(people(4), seed * 7919, 0);
    let steps = 0;
    let last = e.deadline;
    while (!over(e)) {
      advance(e, e.deadline);
      invariants(e);
      if (!over(e)) {
        assert.ok(e.deadline >= last, "time ran backwards");
        last = e.deadline;
      }
      steps += 1;
      assert.ok(steps < 5000, `seed ${seed} never ended`);
    }
    hands += e.hand;
    assert.equal(seated(e).length, 1, "a sitting ends with one player left");
    assert.equal(e.champion, seated(e)[0]);
    assert.equal(e.standings.length, 4);
    assert.equal(e.standings[0].seat, e.champion);
    assert.deepEqual([...e.exits].reverse(), e.standings.slice(1).map((r) => r.seat));
  }
  assert.ok(hands / 300 > 3, "too few hands per sitting");
});

test("rock-paper-scissors: the winner never leaves, the loser only on a loss", () => {
  let losses = 0;
  let ties = 0;
  for (let seed = 1; seed <= 400; seed++) {
    const e = createEngine(people(4), seed, 0);
    while (e.phase !== "duel" && e.phase !== "over") advance(e, e.deadline);
    if (e.phase !== "duel") continue;
    const duel = e.duel!;
    const standings = makeStandings(e);
    assert.equal(duel.loser, standings[standings.length - 1].seat);
    assert.equal(duel.winner, standings[0].seat);
    advance(e, e.deadline);
    assert.equal(e.duel!.stage, "choose");
    // Both choose; the throw follows once both are in.
    throwHand(e, duel.loser, ROCK, e.deadline - 1);
    assert.equal(e.duel!.stage, "choose");
    throwHand(e, duel.winner, seed % 3, e.deadline - 1);
    assert.equal(e.duel!.stage, "chant");
    advance(e, e.deadline);
    const thrown = e.duel!.throws!;
    assert.equal(thrown[String(duel.loser)], ROCK);
    assert.equal(thrown[String(duel.winner)], seed % 3);
    if (seed % 3 === ROCK) {
      ties += 1;
      assert.equal(e.duel!.settled, false);
      advance(e, e.deadline);
      assert.equal(e.duel!.stage, "choose", "a tie is thrown again, fresh");
      assert.deepEqual(e.duel!.picks, {});
    } else {
      assert.equal(e.seats[duel.winner].out, false);
      assert.equal(e.seats[duel.loser].out, beats(seed % 3, ROCK));
      if (beats(seed % 3, ROCK)) losses += 1;
    }
  }
  assert.ok(losses > 0 && ties > 0);
});

test("a table whose people have all gone ends at the next hand", () => {
  const e = createEngine(people(1), 11, 0);
  e.seats[0].user = null;
  while (e.phase !== "over") advance(e, e.deadline);
  assert.equal(e.hand, 1);
});
