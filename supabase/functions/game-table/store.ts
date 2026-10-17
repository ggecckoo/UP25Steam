// The tables' Store on Postgres, through the service-role client: plain
// reads and inserts, and every state change through `game_table_commit`,
// which applies it in one transaction if the version still matches.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { Engine } from "../_shared/game/engine.ts";
import type { Commit, Member, Store, TableRow } from "../_shared/game/service.ts";

export class SupabaseStore implements Store {
  db: SupabaseClient;

  constructor(db: SupabaseClient) {
    this.db = db;
  }

  async insertTable(row: TableRow): Promise<boolean> {
    const { error } = await this.db.from("game_tables").insert({
      id: row.id,
      code: row.code,
      host: row.host,
      status: row.status,
      seats: row.seats,
      state: row.state,
      version: row.version,
      deadline: null,
    });
    if (error && error.code === "23505") return false;
    if (error) throw error;
    return true;
  }

  async table(id: string): Promise<TableRow | null> {
    const { data, error } = await this.db.from("game_tables").select("*").eq("id", id).maybeSingle();
    if (error) throw error;
    return data ? toRow(data) : null;
  }

  async tableByCode(code: string): Promise<TableRow | null> {
    const { data, error } = await this.db.from("game_tables").select("*").eq("code", code).maybeSingle();
    if (error) throw error;
    return data ? toRow(data) : null;
  }

  async members(tableId: string): Promise<Member[]> {
    const { data, error } = await this.db.from("game_table_members").select("*").eq("table_id", tableId);
    if (error) throw error;
    return (data ?? []).map((m) => ({
      tableId: m.table_id,
      userId: m.user_id,
      seat: m.seat,
      name: m.display_name,
      preset: m.preset,
      left: m.left_at !== null,
    }));
  }

  async addMember(member: Member): Promise<boolean> {
    const { error } = await this.db.from("game_table_members").insert({
      table_id: member.tableId,
      user_id: member.userId,
      seat: member.seat,
      display_name: member.name,
      preset: member.preset,
    });
    if (error && error.code === "23505") return false;
    if (error) throw error;
    return true;
  }

  async updateMember(member: Member): Promise<void> {
    const { error } = await this.db
      .from("game_table_members")
      .update({ left_at: member.left ? new Date().toISOString() : null })
      .eq("table_id", member.tableId)
      .eq("user_id", member.userId);
    if (error) throw error;
  }

  async removeMember(tableId: string, userId: string): Promise<void> {
    const { error } = await this.db.from("game_table_members").delete().eq("table_id", tableId).eq("user_id", userId);
    if (error) throw error;
  }

  async engine(tableId: string): Promise<Engine | null> {
    const { data, error } = await this.db.from("game_table_engines").select("engine").eq("table_id", tableId).maybeSingle();
    if (error) throw error;
    return data ? (data.engine as Engine) : null;
  }

  async commit(change: Commit): Promise<number> {
    const { data, error } = await this.db.rpc("game_table_commit", {
      p_table: change.tableId,
      p_expected: change.expected,
      p_status: change.status,
      p_seats: change.seats,
      p_state: change.state,
      p_deadline: change.deadline === null ? null : new Date(change.deadline).toISOString(),
      p_engine: change.engine,
      p_hands: change.hands.map((h) => ({ user_id: h.userId, seat: h.seat, cards: h.cards })),
      p_results: change.results.map((r) => ({ user_id: r.userId, score: r.score, placement: r.placement, won: r.won })),
    });
    if (error) throw error;
    return Number(data);
  }
}

function toRow(data: Record<string, unknown>): TableRow {
  return {
    id: String(data.id),
    code: String(data.code),
    host: String(data.host),
    status: data.status as TableRow["status"],
    seats: data.seats as TableRow["seats"],
    state: (data.state ?? {}) as Record<string, unknown>,
    version: Number(data.version),
    deadline: data.deadline ? Date.parse(String(data.deadline)) : null,
  };
}
