// Tables played over the network: the lobby (create, join by code, leave),
// starting a sitting with bots in the empty seats, and every move after,
// each checked and applied by the engine. Storage is behind `Store`, so the
// edge function runs this against Postgres and the tests against memory.
//
// Every change follows the same path: load the engine and its version, let
// time catch up (`advance`), apply the move, and commit only if no one else
// committed in between; otherwise it starts over from the newer state.

import {
  advance,
  createEngine,
  GameError,
  handOf,
  leave as leaveSeat,
  play as playCard,
  publicView,
  SEATS,
  seatOf,
  throwHand,
} from "./engine.ts";
import type { Engine, SeatSpec } from "./engine.ts";

export type Status = "lobby" | "playing" | "over" | "closed";

export type LobbySeat = { seat: number; name: string; preset: string; taken: boolean };

export type TableRow = {
  id: string;
  code: string;
  host: string;
  status: Status;
  // Public: the lobby's seats before a sitting starts, then the table as
  // every player sees it (engine.publicView).
  seats: LobbySeat[];
  state: Record<string, unknown>;
  version: number;
  deadline: number | null;
};

export type Member = { tableId: string; userId: string; seat: number; name: string; preset: string; left: boolean };

export type Hand = { userId: string; seat: number; cards: unknown[] };

export type Result = { userId: string; score: number; placement: number; won: boolean };

export type Commit = {
  tableId: string;
  expected: number;
  status: Status;
  seats: LobbySeat[];
  state: Record<string, unknown>;
  deadline: number | null;
  engine: Engine | null;
  hands: Hand[];
  results: Result[];
};

export interface Store {
  insertTable(row: TableRow): Promise<boolean>;
  table(id: string): Promise<TableRow | null>;
  tableByCode(code: string): Promise<TableRow | null>;
  members(tableId: string): Promise<Member[]>;
  addMember(member: Member): Promise<boolean>;
  updateMember(member: Member): Promise<void>;
  removeMember(tableId: string, userId: string): Promise<void>;
  engine(tableId: string): Promise<Engine | null>;
  // Applies everything in one transaction if the table is still at
  // `expected`; returns the new version, or -1 if someone got there first.
  commit(change: Commit): Promise<number>;
}

// The six characters of the cast, as the Godot client's roster names them.
export const ROSTER: { preset: string; name: string }[] = [
  { preset: "kaya", name: "Kaya" },
  { preset: "sis", name: "Sis" },
  { preset: "kok", name: "Kök" },
  { preset: "karaca", name: "Karaca" },
  { preset: "sirtlan", name: "Sırtlan" },
  { preset: "dere", name: "Dere" },
];

// No 0/O or 1/I, so a code read out loud is not misheard.
const CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const RETRIES = 6;

export type Clock = () => number;

export class TableService {
  store: Store;
  now: Clock;
  random: () => number;

  constructor(store: Store, now: Clock, random: () => number = Math.random) {
    this.store = store;
    this.now = now;
    this.random = random;
  }

  // --- lobby ---------------------------------------------------------------------------

  async create(user: string, name: string, preset: string): Promise<{ tableId: string; code: string; seat: number }> {
    const chosen = pickPreset([], preset);
    for (let attempt = 0; attempt < 8; attempt++) {
      const row: TableRow = {
        id: crypto.randomUUID(),
        code: this.code(),
        host: user,
        status: "lobby",
        seats: lobbySeats([{ seat: 0, name: cleanName(name, chosen), preset: chosen }]),
        state: {},
        version: 0,
        deadline: null,
      };
      if (!(await this.store.insertTable(row))) continue;
      await this.store.addMember({ tableId: row.id, userId: user, seat: 0, name: cleanName(name, chosen), preset: chosen, left: false });
      return { tableId: row.id, code: row.code, seat: 0 };
    }
    throw new GameError("no_code");
  }

  async join(user: string, code: string, name: string, preset: string): Promise<{ tableId: string; seat: number }> {
    const row = await this.store.tableByCode(code.trim().toUpperCase());
    if (row === null || row.status === "closed") throw new GameError("table_not_found");
    for (let attempt = 0; attempt < RETRIES; attempt++) {
      const members = await this.store.members(row.id);
      const mine = members.find((m) => m.userId === user);
      if (mine) return { tableId: row.id, seat: mine.seat };
      const current = await this.store.table(row.id);
      if (current === null || current.status !== "lobby") throw new GameError("table_started");
      const free = [0, 1, 2, 3].find((seat) => !members.some((m) => m.seat === seat));
      if (free === undefined) throw new GameError("table_full");
      const chosen = pickPreset(members.map((m) => m.preset), preset);
      const member: Member = { tableId: row.id, userId: user, seat: free, name: cleanName(name, chosen), preset: chosen, left: false };
      if (!(await this.store.addMember(member))) continue;
      await this.refreshLobby(row.id);
      return { tableId: row.id, seat: free };
    }
    throw new GameError("busy");
  }

  async leave(user: string, tableId: string): Promise<void> {
    const row = await this.mustTable(tableId);
    const members = await this.store.members(tableId);
    const mine = members.find((m) => m.userId === user && !m.left);
    if (!mine) return;
    if (row.status === "lobby") {
      await this.store.removeMember(tableId, user);
      if (user === row.host) {
        // The host closing an unstarted table sends everyone home.
        await this.commitLobby(tableId, "closed");
      } else {
        await this.refreshLobby(tableId);
      }
      return;
    }
    await this.store.updateMember({ ...mine, left: true });
    if (row.status === "playing") {
      await this.mutate(user, tableId, (engine) => {
        leaveSeat(engine, user);
      }, true);
    }
  }

  async start(user: string, tableId: string): Promise<void> {
    const row = await this.mustTable(tableId);
    if (row.host !== user) throw new GameError("not_host");
    if (row.status !== "lobby") throw new GameError("table_started");
    const members = (await this.store.members(tableId)).filter((m) => !m.left);
    // Empty seats get bots, drawn from the cast nobody picked.
    const taken = members.map((m) => m.preset);
    const spare = ROSTER.filter((r) => !taken.includes(r.preset));
    const specs: SeatSpec[] = [];
    for (let seat = 0; seat < SEATS; seat++) {
      const member = members.find((m) => m.seat === seat);
      if (member) {
        specs.push({ name: member.name, preset: member.preset, user: member.userId });
      } else {
        const bot = spare.shift() ?? ROSTER[seat];
        specs.push({ name: bot.name, preset: bot.preset, user: null });
      }
    }
    const engine = createEngine(specs, Math.floor(this.random() * 2 ** 32), this.now());
    const version = await this.store.commit(this.change(row, "playing", engine, members));
    if (version < 0) throw new GameError("busy");
  }

  // --- play ----------------------------------------------------------------------------

  async play(user: string, tableId: string, cardId: number): Promise<void> {
    await this.mutate(user, tableId, (engine, now) => {
      playCard(engine, this.seatFor(engine, user), cardId, now);
    });
  }

  async throwHand(user: string, tableId: string, choice: number): Promise<void> {
    await this.mutate(user, tableId, (engine, now) => {
      throwHand(engine, this.seatFor(engine, user), choice, now);
    });
  }

  async tick(user: string, tableId: string): Promise<void> {
    // Lets the table's clock catch up: anyone at the table may call it when
    // the public deadline has passed.
    await this.mutate(user, tableId, () => {}, true);
  }

  async state(user: string, tableId: string): Promise<{ table: TableRow; seat: number; hand: unknown[] }> {
    const row = await this.mustTable(tableId);
    const member = (await this.store.members(tableId)).find((m) => m.userId === user);
    if (!member) throw new GameError("not_a_member");
    const engine = await this.store.engine(tableId);
    const hand = engine !== null && engine.seats[member.seat].user === user ? handOf(engine, member.seat) : [];
    return { table: row, seat: member.seat, hand };
  }

  // --- the one way state changes -------------------------------------------------------

  async mutate(user: string, tableId: string, move: (engine: Engine, now: number) => void, quiet = false): Promise<void> {
    // `quiet` moves (a tick, leaving) do nothing once the sitting is over
    // instead of failing: a late clock or a goodbye is not an error.
    for (let attempt = 0; attempt < RETRIES; attempt++) {
      const row = await this.mustTable(tableId);
      if (row.status !== "playing") {
        if (quiet && row.status === "over") return;
        throw new GameError("not_playing");
      }
      const members = await this.store.members(tableId);
      if (!members.some((m) => m.userId === user)) throw new GameError("not_a_member");
      const engine = await this.store.engine(tableId);
      if (engine === null) throw new GameError("not_playing");
      const now = this.now();
      const before = engine.seq;
      advance(engine, now);
      move(engine, now);
      advance(engine, now);
      if (engine.seq === before) return;
      const status: Status = engine.phase === "over" ? "over" : "playing";
      const version = await this.store.commit(this.change(row, status, engine, members));
      if (version >= 0) return;
    }
    throw new GameError("busy");
  }

  change(row: TableRow, status: Status, engine: Engine, members: Member[]): Commit {
    const hands: Hand[] = [];
    engine.seats.forEach((seat, i) => {
      if (seat.user !== null) hands.push({ userId: seat.user, seat: i, cards: handOf(engine, i) });
    });
    // Whoever left mid-sitting sees an empty hand.
    for (const member of members) {
      if (!hands.some((h) => h.userId === member.userId)) hands.push({ userId: member.userId, seat: member.seat, cards: [] });
    }
    let results: Result[] = [];
    if (engine.phase === "over" && !engine.recorded) {
      engine.recorded = true;
      results = this.results(engine, members);
    }
    return {
      tableId: row.id,
      expected: row.version,
      status,
      seats: row.seats,
      state: publicView(engine),
      deadline: engine.phase === "over" ? null : engine.deadline,
      engine,
      hands,
      results,
    };
  }

  results(engine: Engine, members: Member[]): Result[] {
    // Each person who sat down, by their place in the final standings.
    const out: Result[] = [];
    engine.standings.forEach((row, i) => {
      const member = members.find((m) => m.seat === row.seat);
      if (!member) return;
      out.push({ userId: member.userId, score: row.score, placement: i + 1, won: engine.champion === row.seat });
    });
    return out;
  }

  seatFor(engine: Engine, user: string): number {
    const seat = seatOf(engine, user);
    if (seat < 0) throw new GameError("not_seated");
    return seat;
  }

  async mustTable(tableId: string): Promise<TableRow> {
    const row = await this.store.table(tableId);
    if (row === null) throw new GameError("table_not_found");
    return row;
  }

  async refreshLobby(tableId: string): Promise<void> {
    await this.commitLobby(tableId, "lobby");
  }

  async commitLobby(tableId: string, status: Status): Promise<void> {
    for (let attempt = 0; attempt < RETRIES; attempt++) {
      const row = await this.mustTable(tableId);
      if (row.status !== "lobby") return;
      const members = (await this.store.members(tableId)).filter((m) => !m.left);
      const version = await this.store.commit({
        tableId,
        expected: row.version,
        status,
        seats: lobbySeats(members.map((m) => ({ seat: m.seat, name: m.name, preset: m.preset }))),
        state: {},
        deadline: null,
        engine: null,
        hands: [],
        results: [],
      });
      if (version >= 0) return;
    }
    throw new GameError("busy");
  }

  code(): string {
    let out = "";
    for (let i = 0; i < 6; i++) out += CODE_LETTERS[Math.floor(this.random() * CODE_LETTERS.length)];
    return out;
  }
}

function lobbySeats(taken: { seat: number; name: string; preset: string }[]): LobbySeat[] {
  const out: LobbySeat[] = [];
  for (let seat = 0; seat < SEATS; seat++) {
    const who = taken.find((t) => t.seat === seat);
    out.push(who ? { seat, name: who.name, preset: who.preset, taken: true } : { seat, name: "", preset: "", taken: false });
  }
  return out;
}

function pickPreset(taken: string[], wanted: string): string {
  // Each character sits at a table once: a taken pick gets the next free one.
  if (ROSTER.some((r) => r.preset === wanted) && !taken.includes(wanted)) return wanted;
  const free = ROSTER.find((r) => !taken.includes(r.preset));
  return free ? free.preset : ROSTER[0].preset;
}

function cleanName(name: string, preset: string): string {
  const trimmed = (name ?? "").trim().slice(0, 24);
  if (trimmed !== "") return trimmed;
  return ROSTER.find((r) => r.preset === preset)?.name ?? "Oyuncu";
}
