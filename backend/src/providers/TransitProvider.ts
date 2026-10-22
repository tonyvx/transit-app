import type { Alert, RouteInfo, Vehicle } from "../types.ts";

/** Implement this per transit agency/city; the rest of the backend only depends on it. */
export interface TransitProvider {
  readonly id: string;
  getRoutes(): Promise<RouteInfo[]>;
  getVehicles(): Promise<Vehicle[]>;
  getAlerts(): Promise<Alert[]>;
  /** Route polyline(s) as [lat, lon] points. */
  getShapes(routeId: string): Promise<Array<Array<[number, number]>>>;
}
