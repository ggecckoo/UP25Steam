// A Store in memory, behaving like the Postgres one (unique codes and seats,
// versioned commits, results recorded with the commit). For tests and
// local experiments.

import type { Engine } from "./engine.ts";
import type { Commit, Member, Result, Store, TableRow } from "./service.ts";

export class MemoryStore implements Store {
  tables = new Map<string, TableRow>();
  memberRows: Member[] = [];
  engines = new Map<string, Engine>();
  hands = new Map<string, { seat: number; cards: unknown[] }>();
  results: Result[] = [];
  commits = 0;
  // A commit hook the tests use to slip in a competing write.
  beforeCommit: ((change: Commit) => void) | null = null;

  async insertTable(row: TableRow): Promise<boolean> {
    for (const t of this.tables.values()) if (t.code === row.code) return false;
    this.tables.set(row.id, structuredClone(row));
    return true;
  }

  async table(id: string): Promise<TableRow | null> {
    const row = this.tables.get(id);
    return row ? structuredClone(row) : null;
  }

  async tableByCode(code: string): Promise<TableRow | null> {
    for (const t of this.tables.values()) if (t.code === code) return structuredClone(t);
    return null;
  }

  async members(tableId: string): Promise<Member[]> {
    return structuredClone(this.memberRows.filter((m) => m.tableId === tableId));
  }

  async addMember(member: Member): Promise<boolean> {
    const clash = this.memberRows.some((m) => m.tableId === member.tableId && (m.seat === member.seat || m.userId === member.userId));
    if (clash) return false;
    this.memberRows.push(structuredClone(member));
    return true;
  }

  async updateMember(member: Member): Promise<void> {
    const at = this.memberRows.findIndex((m) => m.tableId === member.tableId && m.userId === member.userId);
    if (at >= 0) this.memberRows[at] = structuredClone(member);
  }

  async removeMember(tableId: string, userId: string): Promise<void> {
    this.memberRows = this.memberRows.filter((m) => !(m.tableId === tableId && m.userId === userId));
  }

  async engine(tableId: string): Promise<Engine | null> {
    const engine = this.engines.get(tableId);
    return engine ? structuredClone(engine) : null;
  }

  async commit(change: Commit): Promise<number> {
    if (this.beforeCommit) this.beforeCommit(change);
    const row = this.tables.get(change.tableId);
    if (!row || row.version !== change.expected) return -1;
    row.version += 1;
    row.status = change.status;
    row.seats = structuredClone(change.seats);
    row.state = structuredClone(change.state);
    row.deadline = change.deadline;
    if (change.engine !== null) this.engines.set(change.tableId, structuredClone(change.engine));
    for (const hand of change.hands) this.hands.set(`${change.tableId}/${hand.userId}`, { seat: hand.seat, cards: structuredClone(hand.cards) });
    this.results.push(...structuredClone(change.results));
    this.commits += 1;
    return row.version;
  }

  handOf(tableId: string, userId: string): unknown[] {
    return this.hands.get(`${tableId}/${userId}`)?.cards ?? [];
  }
}
