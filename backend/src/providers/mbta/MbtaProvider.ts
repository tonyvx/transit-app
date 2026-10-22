import type { TransitProvider } from "../TransitProvider.ts";
import type { Alert, RouteInfo, Vehicle } from "../../types.ts";

const BASE = "https://api-v3.mbta.com";
const MPH_TO_MPS = 0.44704;

interface Resource {
  id: string;
  attributes: Record<string, any>;
  relationships?: Record<string, { data: any }>;
}

export class MbtaProvider implements TransitProvider {
  readonly id = "mbta";
  private apiKey: string;
  private fetchFn: typeof fetch;
  private shapeCache = new Map<string, Array<Array<[number, number]>>>();
  private routeCache: RouteInfo[] | null = null;

  constructor(apiKey: string, fetchFn: typeof fetch = fetch) {
    this.apiKey = apiKey;
    this.fetchFn = fetchFn;
  }

  private async get(path: string, params: Record<string, string>): Promise<Resource[]> {
    const url = new URL(BASE + path);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    const res = await this.fetchFn(url, { headers: { "x-api-key": this.apiKey } });
    if (!res.ok) throw new Error(`MBTA ${path} failed: ${res.status}`);
    return ((await res.json()) as { data: Resource[] }).data;
  }

  async getRoutes(): Promise<RouteInfo[]> {
    if (!this.routeCache) {
      const data = await this.get("/routes", { "filter[type]": "2" });
      this.routeCache = data.map((r) => ({
        id: r.id,
        name: r.attributes.long_name,
        color: r.attributes.color ? `#${r.attributes.color}` : null,
      }));
    }
    return this.routeCache;
  }

  async getVehicles(): Promise<Vehicle[]> {
    const data = await this.get("/vehicles", { "filter[route_type]": "2" });
    return data
      .filter((v) => v.attributes.latitude != null && v.attributes.longitude != null)
      .map((v) => ({
        id: v.id,
        routeId: v.relationships?.route?.data?.id ?? "",
        tripId: v.relationships?.trip?.data?.id ?? null,
        directionId: v.attributes.direction_id ?? null,
        label: v.attributes.label ?? null,
        lat: v.attributes.latitude,
        lon: v.attributes.longitude,
        bearing: v.attributes.bearing ?? null,
        // MBTA reports vehicle speed in mph despite docs ambiguity; normalise to m/s.
        speedMps: v.attributes.speed != null ? v.attributes.speed * MPH_TO_MPS : null,
        status: v.attributes.current_status ?? null,
        updatedAt: v.attributes.updated_at,
      }));
  }

  async getAlerts(): Promise<Alert[]> {
    const data = await this.get("/alerts", {
      "filter[route_type]": "2",
      "filter[activity]": "BOARD,EXIT,RIDE",
    });
    return data.map((a) => {
      const informed: any[] = a.attributes.informed_entity ?? [];
      const period = (a.attributes.active_period ?? [])[0];
      return {
        id: a.id,
        effect: a.attributes.effect,
        header: a.attributes.header,
        description: a.attributes.description ?? null,
        severity: a.attributes.severity ?? 0,
        routeIds: [...new Set(informed.map((e) => e.route).filter(Boolean))],
        stopIds: [...new Set(informed.map((e) => e.stop).filter(Boolean))],
        activeFrom: period?.start ?? null,
        activeUntil: period?.end ?? null,
      };
    });
  }

  async getShapes(routeId: string): Promise<Array<Array<[number, number]>>> {
    const cached = this.shapeCache.get(routeId);
    if (cached) return cached;
    const data = await this.get("/shapes", { "filter[route]": routeId });
    const shapes = data.map((s) => decodePolyline(s.attributes.polyline));
    this.shapeCache.set(routeId, shapes);
    return shapes;
  }
}

/** Google encoded polyline (precision 5), as used by the MBTA API. */
export function decodePolyline(str: string): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  let i = 0, lat = 0, lon = 0;
  const next = () => {
    let result = 0, shift = 0, b: number;
    do {
      b = str.charCodeAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return result & 1 ? ~(result >> 1) : result >> 1;
  };
  while (i < str.length) {
    lat += next();
    lon += next();
    out.push([lat / 1e5, lon / 1e5]);
  }
  return out;
}
