import { DatabaseSync } from "node:sqlite";
import type { GpsReport, IncidentKind, IncidentReport } from "../types.ts";

export interface Store {
  addPing(p: GpsReport): void;
  recentPings(sinceMs: number): Map<string, GpsReport[]>;
  deleteSession(sessionId: string): void;
  addIncident(i: Omit<IncidentReport, "id">): IncidentReport;
  recentIncidents(sinceMs: number): IncidentReport[];
  prune(pingsBeforeMs: number): void;
}

/** SQLite implementation; swap for Postgres behind the same interface later. */
export class SqliteStore implements Store {
  private db: DatabaseSync;

  constructor(path = ":memory:") {
    this.db = new DatabaseSync(path);
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS pings (
        session_id TEXT NOT NULL, lat REAL, lon REAL, accuracy REAL,
        speed REAL, heading REAL, ts INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS pings_ts ON pings(ts);
      CREATE TABLE IF NOT EXISTS incidents (
        id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT, level INTEGER,
        trip_id TEXT, vehicle_id TEXT, note TEXT, created_at INTEGER NOT NULL
      );
    `);
  }

  addPing(p: GpsReport): void {
    this.db
      .prepare("INSERT INTO pings VALUES (?,?,?,?,?,?,?)")
      .run(p.sessionId, p.lat, p.lon, p.accuracyM, p.speedMps, p.heading, p.timestamp);
  }

  recentPings(sinceMs: number): Map<string, GpsReport[]> {
    const rows = this.db.prepare("SELECT * FROM pings WHERE ts >= ? ORDER BY ts").all(sinceMs) as any[];
    const out = new Map<string, GpsReport[]>();
    for (const r of rows) {
      const list = out.get(r.session_id) ?? [];
      list.push({
        sessionId: r.session_id, lat: r.lat, lon: r.lon, accuracyM: r.accuracy,
        speedMps: r.speed, heading: r.heading, timestamp: r.ts,
      });
      out.set(r.session_id, list);
    }
    return out;
  }

  deleteSession(sessionId: string): void {
    this.db.prepare("DELETE FROM pings WHERE session_id = ?").run(sessionId);
  }

  addIncident(i: Omit<IncidentReport, "id">): IncidentReport {
    const r = this.db
      .prepare("INSERT INTO incidents (kind, level, trip_id, vehicle_id, note, created_at) VALUES (?,?,?,?,?,?)")
      .run(i.kind, i.level, i.tripId, i.vehicleId, i.note, i.createdAt);
    return { ...i, id: Number(r.lastInsertRowid) };
  }

  recentIncidents(sinceMs: number): IncidentReport[] {
    const rows = this.db.prepare("SELECT * FROM incidents WHERE created_at >= ? ORDER BY created_at DESC").all(sinceMs) as any[];
    return rows.map((r) => ({
      id: r.id, kind: r.kind as IncidentKind, level: r.level, tripId: r.trip_id,
      vehicleId: r.vehicle_id, note: r.note, createdAt: r.created_at,
    }));
  }

  prune(pingsBeforeMs: number): void {
    this.db.prepare("DELETE FROM pings WHERE ts < ?").run(pingsBeforeMs);
  }
}
