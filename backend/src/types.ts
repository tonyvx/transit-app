export interface Vehicle {
  id: string;
  routeId: string;
  tripId: string | null;
  directionId: number | null;
  label: string | null;
  lat: number;
  lon: number;
  bearing: number | null;
  speedMps: number | null;
  status: string | null;
  updatedAt: string;
}

export interface Alert {
  id: string;
  effect: string;
  header: string;
  description: string | null;
  severity: number;
  routeIds: string[];
  stopIds: string[];
  activeFrom: string | null;
  activeUntil: string | null;
}

export interface RouteInfo {
  id: string;
  name: string;
  color: string | null;
}

export interface GpsReport {
  sessionId: string;
  lat: number;
  lon: number;
  accuracyM: number;
  speedMps: number | null;
  heading: number | null;
  timestamp: number;
}

export type IncidentKind = "stoppage" | "crowding";

export interface IncidentReport {
  id: number;
  kind: IncidentKind;
  level: number | null;
  tripId: string | null;
  vehicleId: string | null;
  note: string | null;
  createdAt: number;
}

export interface CrowdEstimate {
  vehicleId: string;
  tripId: string | null;
  lat: number;
  lon: number;
  confidence: number;
  reporters: number;
  updatedAt: string;
}
