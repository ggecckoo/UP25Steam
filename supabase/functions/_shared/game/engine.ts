// 30-80 rules for a table played over the network: the same game as the
// Godot client's match.gd, kept here as the authority. Pure and
// deterministic: every random draw comes from the engine's own seeded
// generator and every timed step from the `now` (epoch ms) it is given, so
// the edge function can replay it and the tests can drive it.
//
// The engine never waits. Each state that waits on someone carries a
// `deadline`; `advance(engine, now)` plays whatever is due by then: a bot's
// turn, a human's turn that ran out (played for them as a bot would), the
// end of a reveal, each stage of the rock-paper-scissors throw.

export const SEATS = 4;
export const ROUNDS = 8;
export const HAND_SIZE = 7;
export const DECK_SIZE = 28;
export const PENALTY_PER_CARD = 4;
export const LIMIT = 30;
export const CAP = 80;
// Limit and cap by how many are still seated (see match.gd).
export const TARGETS: Record<number, [number, number]> = { 4: [LIMIT, CAP], 3: [23, 60], 2: [14, 40] };
// A, 3, 5, 7, 9, J, K by rank index, as match.gd numbers them.
export const RANKS = [0, 2, 4, 6, 8, 10, 12];

export const OUTCOME_OVER = 0;
export const OUTCOME_EXACT = 1;
export const OUTCOME_CAP = 2;
export const OUTCOME_UNDER = 3;

export const ROCK = 0;
export const PAPER = 1;
export const SCISSORS = 2;

// Milliseconds the table gives each step: time for the clients to show the
// deal, a reveal, the stages of a throw; a human's time to play or throw;
// a bot's thinking.
export const TIMING = {
  deal: 6000,
  roundLead: 900,
  turn: 30000,
  botThink: [1200, 2900] as [number, number],
  firstThink: 450,
  reveal: 9500,
  duelIntro: 3400,
  duelChoose: 15000,
  chant: 1500,
  show: 2400,
  tieShow: 1600,
  after: 1400,
  walkOut: 9000,
};

export type Card = { id: number; rank: number; suit: number };
export type Played = { card: Card; by: number };

export type Seat = {
  name: string;
  preset: string;
  // Auth user playing this seat; null for a bot (or a player who left).
  user: string | null;
  out: boolean;
  leftAfter: number;
  hand: Card[];
};

export type Row = { seat: number; name: string; cards: number; value: number; penalty: number; score: number; leftAfter: number };

export type DuelStage = "intro" | "choose" | "chant" | "show" | "after";

export type Duel = {
  loser: number;
  winner: number;
  stage: DuelStage;
  // Throws chosen so far this throw; hidden until both hands come down.
  picks: Record<string, number>;
  throws: Record<string, number> | null;
  ties: number;
  settled: boolean;
  out: boolean;
};

export type LastRound = {
  hand: number;
  round: number;
  holder: number;
  played: Played[];
  total: number;
  outcome: number;
  // Cards each seat drew from this round's pile, by card id.
  drawn: Record<string, number[]>;
};

export type Phase = "playing" | "reveal" | "duel" | "over";

export type Engine = {
  rng: number;
  nextId: number;
  phase: Phase;
  hand: number;
  round: number;
  holder: number;
  table: Played[];
  middle: Card[];
  deadline: number;
  last: LastRound | null;
  standings: Row[];
  exits: number[];
  champion: number;
  duel: Duel | null;
  seats: Seat[];
  // Bumped by every change, so clients can tell states apart.
  seq: number;
  recorded: boolean;
};

export class GameError extends Error {
  code: string;
  constructor(code: string) {
    super(code);
    this.code = code;
  }
}

// --- cards ------------------------------------------------------------------------

export function value(card: Card): number {
  switch (card.rank) {
    case 0:
      return 1;
    case 10:
      return 15;
    case 12:
      return 20;
    default:
      return card.rank + 1;
  }
}

export function handValue(hand: Card[]): number {
  return hand.reduce((sum, card) => sum + value(card), 0);
}

export function outcomeFor(total: number, limit = LIMIT, cap = CAP): number {
  if (total === cap) return OUTCOME_CAP;
  if (total > limit) return OUTCOME_OVER;
  if (total === limit) return OUTCOME_EXACT;
  return OUTCOME_UNDER;
}

export function targetFor(seated: number): [number, number] {
  if (seated <= 0) return TARGETS[SEATS];
  return TARGETS[Math.min(Math.max(seated, 2), SEATS)];
}

export function draws(outcome: number, holder: number, seats: number[]): number[] {
  const plan = [0, 0, 0, 0];
  if (outcome === OUTCOME_EXACT || outcome === OUTCOME_CAP) {
    for (const seat of seats) if (seat !== holder) plan[seat] = 1;
  } else if (outcome === OUTCOME_UNDER) {
    plan[holder] = 1;
  }
  return plan;
}

export function beats(a: number, b: number): boolean {
  return (a - b + 3) % 3 === 1;
}

function cardLess(a: Card, b: Card): boolean {
  if (value(a) !== value(b)) return value(a) < value(b);
  if (a.suit !== b.suit) return a.suit < b.suit;
  return a.id < b.id;
}

export function sortHand(hand: Card[]): Card[] {
  return [...hand].sort((a, b) => (cardLess(a, b) ? -1 : cardLess(b, a) ? 1 : 0));
}

// --- randomness ----------------------------------------------------------------------

export function random(e: Engine): number {
  // mulberry32
  e.rng = (e.rng + 0x6d2b79f5) >>> 0;
  let t = e.rng;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

function randInt(e: Engine, lo: number, hi: number): number {
  return lo + Math.floor(random(e) * (hi - lo + 1));
}

function shuffle<T>(e: Engine, items: T[]): void {
  for (let i = items.length - 1; i > 0; i--) {
    const j = randInt(e, 0, i);
    const tmp = items[i];
    items[i] = items[j];
    items[j] = tmp;
  }
}

// --- the table ------------------------------------------------------------------------

export type SeatSpec = { name: string; preset: string; user: string | null };

export function createEngine(specs: SeatSpec[], seed: number, now: number): Engine {
  if (specs.length !== SEATS) throw new GameError("seats");
  const e: Engine = {
    rng: seed >>> 0,
    nextId: 0,
    phase: "playing",
    hand: 1,
    round: 1,
    holder: 0,
    table: [],
    middle: [],
    deadline: now,
    last: null,
    standings: [],
    exits: [],
    champion: -1,
    duel: null,
    seats: specs.map((spec) => ({ name: spec.name, preset: spec.preset, user: spec.user, out: false, leftAfter: 0, hand: [] })),
    seq: 0,
    recorded: false,
  };
  deal(e);
  startRound(e, now, TIMING.deal);
  return e;
}

export function seated(e: Engine): number[] {
  const out: number[] = [];
  e.seats.forEach((seat, i) => {
    if (!seat.out) out.push(i);
  });
  return out;
}

export function order(e: Engine): number[] {
  const out: number[] = [];
  for (let i = 0; i < SEATS; i++) {
    const seat = (e.holder + i) % SEATS;
    if (!e.seats[seat].out) out.push(seat);
  }
  return out;
}

export function limits(e: Engine): [number, number] {
  return targetFor(seated(e).length);
}

export function acting(e: Engine): number {
  if (e.phase !== "playing") return -1;
  const seats = order(e);
  return e.table.length < seats.length ? seats[e.table.length] : -1;
}

export function isBot(e: Engine, seat: number): boolean {
  return e.seats[seat].user === null;
}

function deal(e: Engine): void {
  const deck: Card[] = [];
  for (const rank of RANKS) {
    for (let suit = 0; suit < 4; suit++) {
      e.nextId += 1;
      deck.push({ id: e.nextId, rank, suit });
    }
  }
  shuffle(e, deck);
  const seats = seated(e);
  for (const seat of e.seats) seat.hand = [];
  seats.forEach((seat, k) => {
    e.seats[seat].hand = sortHand(deck.slice(k * HAND_SIZE, (k + 1) * HAND_SIZE));
  });
  e.middle = deck.slice(seats.length * HAND_SIZE);
  e.holder = seats[randInt(e, 0, seats.length - 1)];
  e.round = 1;
  e.standings = [];
  e.table = [];
}

function startRound(e: Engine, now: number, lead: number): void {
  e.phase = "playing";
  e.table = [];
  armTurn(e, now, lead);
}

function armTurn(e: Engine, now: number, lead = 0): void {
  const seat = acting(e);
  if (seat < 0) return;
  if (e.seats[seat].hand.length === 0) {
    finishHand(e, now);
    return;
  }
  if (isBot(e, seat)) {
    let think = TIMING.botThink[0] + random(e) * (TIMING.botThink[1] - TIMING.botThink[0]);
    if (e.table.length === 0) think += TIMING.firstThink;
    e.deadline = now + lead + Math.round(think);
  } else {
    e.deadline = now + lead + TIMING.turn;
  }
}

// What a bot plays, and what a human who ran out of time plays: the same
// choice as match.gd's AI.
export function pick(e: Engine, seat: number): Card {
  const hand = e.seats[seat].hand;
  let low = hand[0];
  let high = hand[0];
  for (const card of hand) {
    if (value(card) < value(low)) low = card;
    if (value(card) >= value(high)) high = card;
  }
  if (seat === e.holder) return high;
  const running = e.table.reduce((sum, p) => sum + value(p.card), 0);
  const after = order(e).length - 1 - e.table.length;
  const limit = limits(e)[0];
  if (running + value(low) + after > limit) return high;
  if (running + value(high) + after * 20 <= limit) return high;
  if (random(e) < 0.18 + e.round * 0.06) return high;
  return low;
}

export function play(e: Engine, seat: number, cardId: number, now: number): void {
  if (e.phase !== "playing") throw new GameError("not_playing");
  if (acting(e) !== seat) throw new GameError("not_your_turn");
  const at = e.seats[seat].hand.findIndex((card) => card.id === cardId);
  if (at < 0) throw new GameError("card_not_in_hand");
  place(e, seat, e.seats[seat].hand[at], now);
}

function place(e: Engine, seat: number, card: Card, now: number): void {
  e.seats[seat].hand = e.seats[seat].hand.filter((c) => c.id !== card.id);
  e.table.push({ card, by: seat });
  e.seq += 1;
  if (e.table.length >= order(e).length) {
    resolveRound(e, now);
    return;
  }
  armTurn(e, now);
}

function resolveRound(e: Engine, now: number): void {
  // The round's cards go face up, the total decides who draws, and the
  // holder passes on; the clients show all that over the reveal.
  const [limit, cap] = limits(e);
  const total = e.table.reduce((sum, p) => sum + value(p.card), 0);
  const outcome = outcomeFor(total, limit, cap);
  const pile = e.table.map((p) => p.card);
  shuffle(e, pile);
  pile.push(...e.middle);
  const plan = draws(outcome, e.holder, seated(e));
  const drawn: Record<string, number[]> = {};
  for (const seat of order(e)) {
    const count = Math.min(plan[seat], pile.length);
    if (count <= 0) continue;
    const taken = pile.splice(0, count);
    e.seats[seat].hand = sortHand([...e.seats[seat].hand, ...taken]);
    drawn[String(seat)] = taken.map((card) => card.id);
  }
  e.middle = pile;
  e.last = { hand: e.hand, round: e.round, holder: e.holder, played: e.table, total, outcome, drawn };
  e.holder = nextSeat(e, e.holder);
  e.table = [];
  e.phase = "reveal";
  e.deadline = now + TIMING.reveal;
  e.seq += 1;
}

function nextSeat(e: Engine, seat: number): number {
  for (let step = 1; step <= SEATS; step++) {
    const next = (seat + step) % SEATS;
    if (!e.seats[next].out) return next;
  }
  return seat;
}

function finishHand(e: Engine, now: number): void {
  if (e.phase === "duel" || e.phase === "over") return;
  for (const p of e.table) e.middle.push(p.card);
  e.table = [];
  e.standings = makeStandings(e);
  e.seq += 1;
  if (e.standings.length < 2 || decided(e)) {
    closeSession(e);
    return;
  }
  const loser = e.standings[e.standings.length - 1].seat;
  const winner = e.standings[0].seat;
  e.phase = "duel";
  e.duel = { loser, winner, stage: "intro", picks: {}, throws: null, ties: 0, settled: false, out: false };
  e.deadline = now + TIMING.duelIntro;
}

export function makeStandings(e: Engine): Row[] {
  const rows: Row[] = [];
  e.seats.forEach((seat, i) => {
    if (seat.out) return;
    const penalty = seat.hand.length * PENALTY_PER_CARD;
    rows.push({ seat: i, name: seat.name, cards: seat.hand.length, value: handValue(seat.hand), penalty, score: handValue(seat.hand) + penalty, leftAfter: 0 });
  });
  rows.sort((a, b) => (a.score !== b.score ? a.score - b.score : a.cards !== b.cards ? a.cards - b.cards : a.seat - b.seat));
  return rows;
}

// --- rock-paper-scissors after a hand -------------------------------------------------

export function throwHand(e: Engine, seat: number, choice: number, now: number): void {
  const duel = e.duel;
  if (e.phase !== "duel" || duel === null) throw new GameError("no_duel");
  if (seat !== duel.loser && seat !== duel.winner) throw new GameError("not_in_duel");
  if (duel.stage !== "intro" && duel.stage !== "choose") throw new GameError("not_choosing");
  if (choice !== ROCK && choice !== PAPER && choice !== SCISSORS) throw new GameError("bad_throw");
  duel.picks[String(seat)] = choice;
  e.seq += 1;
  if (duel.stage === "choose" && picked(e)) {
    duel.stage = "chant";
    e.deadline = now + TIMING.chant;
  }
}

function picked(e: Engine): boolean {
  const duel = e.duel as Duel;
  for (const seat of [duel.loser, duel.winner]) {
    if (!isBot(e, seat) && duel.picks[String(seat)] === undefined) return false;
  }
  return true;
}

function stepDuel(e: Engine, now: number): void {
  const duel = e.duel as Duel;
  switch (duel.stage) {
    case "intro":
      duel.stage = "choose";
      e.deadline = now + TIMING.duelChoose;
      if (picked(e)) {
        duel.stage = "chant";
        e.deadline = now + TIMING.chant;
      }
      break;
    case "choose":
      // Out of time: whoever has not thrown throws at random.
      duel.stage = "chant";
      e.deadline = now + TIMING.chant;
      break;
    case "chant": {
      const thrown: Record<string, number> = {};
      for (const seat of [duel.loser, duel.winner]) {
        const own = duel.picks[String(seat)];
        thrown[String(seat)] = own !== undefined && !isBot(e, seat) ? own : randInt(e, ROCK, SCISSORS);
      }
      duel.throws = thrown;
      duel.picks = {};
      if (thrown[String(duel.loser)] === thrown[String(duel.winner)]) {
        duel.ties += 1;
        duel.stage = "show";
        e.deadline = now + TIMING.tieShow;
      } else {
        settle(e, beats(thrown[String(duel.winner)], thrown[String(duel.loser)]));
        duel.stage = "show";
        e.deadline = now + TIMING.show;
      }
      break;
    }
    case "show":
      if (!duel.settled) {
        // A tie: both throw again, fresh.
        duel.throws = null;
        duel.stage = "choose";
        e.deadline = now + TIMING.duelChoose;
        if (picked(e)) {
          duel.stage = "chant";
          e.deadline = now + TIMING.chant;
        }
      } else {
        duel.stage = "after";
        e.deadline = now + TIMING.after + (duel.out ? TIMING.walkOut : 0);
      }
      break;
    case "after":
      if (decided(e)) {
        closeSession(e);
      } else {
        nextHand(e, now);
      }
      break;
  }
  e.seq += 1;
}

function settle(e: Engine, loserOut: boolean): void {
  // Only the last-placed player has anything at stake; the hand's winner
  // keeps the seat whatever they throw.
  const duel = e.duel as Duel;
  duel.settled = true;
  duel.out = loserOut;
  if (loserOut) {
    const gone = e.seats[duel.loser];
    gone.out = true;
    gone.leftAfter = e.hand;
    e.middle.push(...gone.hand);
    gone.hand = [];
    e.exits.push(duel.loser);
  }
}

export function decided(e: Engine): boolean {
  // Over once one player is left, or once no one at the table is a person.
  const seats = seated(e);
  return seats.length <= 1 || seats.every((seat) => isBot(e, seat));
}

function nextHand(e: Engine, now: number): void {
  e.hand += 1;
  e.duel = null;
  e.last = null;
  deal(e);
  startRound(e, now, TIMING.deal);
}

function closeSession(e: Engine): void {
  if (e.phase === "over") return;
  e.phase = "over";
  e.duel = null;
  e.deadline = 0;
  const seats = seated(e);
  e.champion = seats.length === 1 ? seats[0] : -1;
  const rows = makeStandings(e);
  for (let i = e.exits.length - 1; i >= 0; i--) {
    const seat = e.exits[i];
    rows.push({ seat, name: e.seats[seat].name, cards: 0, value: 0, penalty: 0, score: 0, leftAfter: e.seats[seat].leftAfter });
  }
  e.standings = rows;
  e.seq += 1;
}

// --- time ------------------------------------------------------------------------------

export function advance(e: Engine, now: number): boolean {
  // Plays everything due by `now`; true if anything changed.
  let changed = false;
  for (let guard = 0; guard < 200; guard++) {
    if (e.phase === "over" || now < e.deadline) break;
    if (e.phase === "playing") {
      const seat = acting(e);
      if (seat < 0) break;
      place(e, seat, pick(e, seat), e.deadline);
    } else if (e.phase === "reveal") {
      const at = e.deadline;
      if (e.round >= ROUNDS) {
        finishHand(e, at);
      } else {
        e.round += 1;
        startRound(e, at, TIMING.roundLead);
        e.seq += 1;
      }
    } else if (e.phase === "duel") {
      stepDuel(e, e.deadline);
    }
    changed = true;
  }
  return changed;
}

// --- seats changing hands ------------------------------------------------------------

export function leave(e: Engine, user: string): number {
  // A player walking away mid-sitting: a bot takes over their seat.
  const seat = e.seats.findIndex((s) => s.user === user);
  if (seat < 0) return -1;
  e.seats[seat].user = null;
  e.seq += 1;
  return seat;
}

export function seatOf(e: Engine, user: string): number {
  return e.seats.findIndex((s) => s.user === user);
}

// --- what each player may see ----------------------------------------------------------

export function publicView(e: Engine): Record<string, unknown> {
  // Everything on and around the table that every player can see: no
  // hand's cards and no card face down on the felt.
  const [limit, cap] = limits(e);
  const duel = e.duel;
  return {
    phase: e.phase,
    hand: e.hand,
    round: e.round,
    rounds: ROUNDS,
    holder: e.holder,
    limit,
    cap,
    turn: acting(e),
    deadline: e.deadline,
    seq: e.seq,
    seats: e.seats.map((s, i) => ({ seat: i, name: s.name, preset: s.preset, bot: s.user === null, out: s.out, leftAfter: s.leftAfter, cards: s.hand.length })),
    table: e.table.map((p) => ({ by: p.by })),
    middle: e.middle.length,
    last: e.last,
    duel: duel === null
      ? null
      : {
        loser: duel.loser,
        winner: duel.winner,
        stage: duel.stage,
        chosen: Object.keys(duel.picks).map(Number),
        throws: duel.throws,
        ties: duel.ties,
        settled: duel.settled,
        out: duel.out,
      },
    standings: e.standings,
    exits: e.exits,
    champion: e.champion,
  };
}

export function handOf(e: Engine, seat: number): Card[] {
  return e.seats[seat].hand;
}

export function cardCount(e: Engine): number {
  return e.middle.length + e.table.length + e.seats.reduce((sum, s) => sum + s.hand.length, 0);
}
