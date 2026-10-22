import type { CrowdEstimate, GpsReport, Vehicle } from "../types.ts";
import { bearingDiff, haversineM } from "./geo.ts";

export interface MatcherOptions {
  windowMs: number;
  maxCandidateM: number;
  minPings: number;
  minConfidence: number;
  minMovingMps: number;
}

export const DEFAULTS: MatcherOptions = {
  windowMs: 3 * 60_000,
  maxCandidateM: 2000,
  minPings: 3,
  minConfidence: 0.6,
  minMovingMps: 3,
};

interface Match {
  vehicleId: string;
  confidence: number;
  pings: number;
}

/** Scores how well a window of pings from one session fits each official vehicle. */
export function matchSession(
  pings: GpsReport[],
  vehicles: Vehicle[],
  opts: MatcherOptions = DEFAULTS,
): Match | null {
  const moving = pings.filter((p) => p.accuracyM <= 100);
  if (moving.length < opts.minPings || vehicles.length === 0) return null;

  const scores = vehicles.map((v) => {
    let total = 0;
    for (const p of moving) {
      const d = haversineM(p.lat, p.lon, v.lat, v.lon);
      const tolerance = Math.max(150, p.accuracyM * 2);
      let s = d > opts.maxCandidateM ? 0 : Math.exp(-((d / tolerance) ** 2));
      if (s > 0 && p.heading != null && v.bearing != null && (p.speedMps ?? 0) > opts.minMovingMps) {
        s *= bearingDiff(p.heading, v.bearing) < 60 ? 1 : 0.4;
      }
      if (s > 0 && p.speedMps != null && v.speedMps != null) {
        s *= Math.abs(p.speedMps - v.speedMps) < 8 ? 1 : 0.6;
      }
      total += s;
    }
    return { v, score: total / moving.length };
  });

  scores.sort((a, b) => b.score - a.score);
  const best = scores[0];
  const second = scores[1]?.score ?? 0;
  if (best.score <= 0) return null;

  // Confidence rewards a strong fit, a clear margin over the runner-up and more evidence.
  const margin = best.score - second;
  const evidence = Math.min(1, moving.length / (opts.minPings * 2));
  const confidence = Math.min(1, best.score * (0.5 + margin) * (0.5 + 0.5 * evidence));
  return { vehicleId: best.v.id, confidence, pings: moving.length };
}

/** Combines all sessions' matches into one estimate per vehicle. */
export function estimateCrowdPositions(
  sessions: Map<string, GpsReport[]>,
  vehicles: Vehicle[],
  now: number,
  opts: MatcherOptions = DEFAULTS,
): CrowdEstimate[] {
  const byVehicle = new Map<string, Array<{ ping: GpsReport; confidence: number }>>();
  for (const [, all] of sessions) {
    const pings = all.filter((p) => now - p.timestamp <= opts.windowMs).sort((a, b) => a.timestamp - b.timestamp);
    const m = matchSession(pings, vehicles, opts);
    if (!m || m.confidence < opts.minConfidence) continue;
    const list = byVehicle.get(m.vehicleId) ?? [];
    list.push({ ping: pings[pings.length - 1], confidence: m.confidence });
    byVehicle.set(m.vehicleId, list);
  }

  const out: CrowdEstimate[] = [];
  for (const [vehicleId, items] of byVehicle) {
    const w = items.reduce((s, i) => s + i.confidence / Math.max(10, i.ping.accuracyM), 0);
    const lat = items.reduce((s, i) => s + (i.ping.lat * i.confidence) / Math.max(10, i.ping.accuracyM), 0) / w;
    const lon = items.reduce((s, i) => s + (i.ping.lon * i.confidence) / Math.max(10, i.ping.accuracyM), 0) / w;
    const avgConf = items.reduce((s, i) => s + i.confidence, 0) / items.length;
    // More independent riders on the same train increases trust, with diminishing returns.
    const confidence = Math.min(1, avgConf + 0.1 * Math.log2(items.length));
    const latest = Math.max(...items.map((i) => i.ping.timestamp));
    out.push({
      vehicleId,
      tripId: vehicles.find((v) => v.id === vehicleId)?.tripId ?? null,
      lat,
      lon,
      confidence,
      reporters: items.length,
      updatedAt: new Date(latest).toISOString(),
    });
  }
  return out;
}
