import { test } from "node:test";
import assert from "node:assert/strict";
import { estimateCrowdPositions } from "../src/matching/matcher.ts";
import { decodePolyline } from "../src/providers/mbta/MbtaProvider.ts";
import type { GpsReport, Vehicle } from "../src/types.ts";

const veh = (id: string, lat: number, lon: number): Vehicle => ({
  id, routeId: "CR-Test", tripId: `trip-${id}`, directionId: 0, label: id, lat, lon,
  bearing: 90, speedMps: 20, status: "IN_TRANSIT_TO", updatedAt: "",
});
const pings = (sid: string, lat: number, lon: number, n = 5, now = 1_000_000): GpsReport[] =>
  Array.from({ length: n }, (_, i) => ({
    sessionId: sid, lat, lon, accuracyM: 15, speedMps: 21, heading: 85, timestamp: now - i * 10_000,
  }));

test("matches a rider to the nearest train", () => {
  const vehicles = [veh("A", 42.0, -71.0), veh("B", 42.05, -71.0)];
  const est = estimateCrowdPositions(new Map([["s1", pings("s1", 42.0003, -71.0)]]), vehicles, 1_000_000);
  assert.equal(est.length, 1);
  assert.equal(est[0].vehicleId, "A");
  assert.ok(est[0].confidence >= 0.6);
});

test("does not match with too little evidence", () => {
  const est = estimateCrowdPositions(new Map([["s1", pings("s1", 42.0, -71.0, 2)]]), [veh("A", 42.0, -71.0)], 1_000_000);
  assert.equal(est.length, 0);
});

test("rejects ambiguous matches between two co-located trains", () => {
  const vehicles = [veh("A", 42.0, -71.0), veh("B", 42.0001, -71.0)];
  const est = estimateCrowdPositions(new Map([["s1", pings("s1", 42.00005, -71.0)]]), vehicles, 1_000_000);
  assert.equal(est.length, 0);
});

test("ignores riders far from every train", () => {
  const est = estimateCrowdPositions(new Map([["s1", pings("s1", 43.0, -71.0)]]), [veh("A", 42.0, -71.0)], 1_000_000);
  assert.equal(est.length, 0);
});

test("decodes polylines", () => {
  const pts = decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
  assert.deepEqual(pts[0], [38.5, -120.2]);
});
