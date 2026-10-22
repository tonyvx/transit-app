import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { TransitProvider } from "./providers/TransitProvider.ts";
import type { Store } from "./store/store.ts";
import { estimateCrowdPositions } from "./matching/matcher.ts";
import type { GpsReport, IncidentKind } from "./types.ts";

const CACHE_MS = 5_000;
const INCIDENT_TTL_MS = 60 * 60_000;

class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function readJson(req: IncomingMessage): Promise<any> {
  let size = 0;
  const chunks: Buffer[] = [];
  for await (const c of req) {
    size += c.length;
    if (size > 64_000) throw new HttpError(413, "body too large");
    chunks.push(c);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString() || "{}");
  } catch {
    throw new HttpError(400, "invalid JSON");
  }
}

const num = (v: unknown, name: string, min = -Infinity, max = Infinity): number => {
  if (typeof v !== "number" || !Number.isFinite(v) || v < min || v > max) throw new HttpError(400, `invalid ${name}`);
  return v;
};
const optNum = (v: unknown, name: string) => (v == null ? null : num(v, name));

export function createApp(provider: TransitProvider, store: Store, now: () => number = Date.now) {
  let cache: { at: number; vehicles: Awaited<ReturnType<TransitProvider["getVehicles"]>> } | null = null;
  const vehicles = async () => {
    if (!cache || now() - cache.at > CACHE_MS) cache = { at: now(), vehicles: await provider.getVehicles() };
    return cache.vehicles;
  };

  const route = async (req: IncomingMessage, url: URL): Promise<unknown> => {
    const m = req.method;
    const p = url.pathname;

    if (m === "GET" && p === "/v1/health") return { ok: true, provider: provider.id };
    if (m === "GET" && p === "/v1/routes") return provider.getRoutes();
    if (m === "GET" && p === "/v1/alerts") return provider.getAlerts();

    const shape = p.match(/^\/v1\/routes\/([^/]+)\/shapes$/);
    if (m === "GET" && shape) return provider.getShapes(decodeURIComponent(shape[1]));

    if (m === "GET" && p === "/v1/vehicles") {
      const official = await vehicles();
      const t = now();
      const crowd = estimateCrowdPositions(store.recentPings(t - 3 * 60_000), official, t);
      const byId = new Map(crowd.map((c) => [c.vehicleId, c]));
      return { fetchedAt: new Date(t).toISOString(), vehicles: official.map((v) => ({ ...v, crowd: byId.get(v.id) ?? null })) };
    }

    if (m === "POST" && p === "/v1/gps") {
      const b = await readJson(req);
      const sessionId = String(b.sessionId ?? "");
      if (!/^[A-Za-z0-9-]{8,64}$/.test(sessionId)) throw new HttpError(400, "invalid sessionId");
      const report: GpsReport = {
        sessionId,
        lat: num(b.lat, "lat", -90, 90),
        lon: num(b.lon, "lon", -180, 180),
        accuracyM: num(b.accuracyM, "accuracyM", 0, 10_000),
        speedMps: optNum(b.speedMps, "speedMps"),
        heading: optNum(b.heading, "heading"),
        timestamp: Math.min(num(b.timestamp, "timestamp", 0), now()),
      };
      if (now() - report.timestamp > 5 * 60_000) throw new HttpError(400, "stale report");
      store.addPing(report);
      return { ok: true };
    }

    const del = p.match(/^\/v1\/gps\/([A-Za-z0-9-]{8,64})$/);
    if (m === "DELETE" && del) {
      store.deleteSession(del[1]);
      return { ok: true };
    }

    if (m === "POST" && p === "/v1/incidents") {
      const b = await readJson(req);
      if (b.kind !== "stoppage" && b.kind !== "crowding") throw new HttpError(400, "invalid kind");
      const level = b.kind === "crowding" ? num(b.level, "level", 1, 3) : null;
      return store.addIncident({
        kind: b.kind as IncidentKind,
        level,
        tripId: typeof b.tripId === "string" ? b.tripId : null,
        vehicleId: typeof b.vehicleId === "string" ? b.vehicleId : null,
        note: typeof b.note === "string" ? b.note.slice(0, 280) : null,
        createdAt: now(),
      });
    }

    if (m === "GET" && p === "/v1/incidents") return store.recentIncidents(now() - INCIDENT_TTL_MS);

    throw new HttpError(404, "not found");
  };

  return createServer(async (req: IncomingMessage, res: ServerResponse) => {
    try {
      const body = await route(req, new URL(req.url ?? "/", "http://localhost"));
      res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(body));
    } catch (e) {
      const status = e instanceof HttpError ? e.status : 502;
      const message = e instanceof HttpError ? e.message : "upstream error";
      if (!(e instanceof HttpError)) console.error(e);
      res.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify({ error: message }));
    }
  });
}
