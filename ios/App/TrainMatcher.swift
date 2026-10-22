import CoreLocation
import Foundation

/// Scores the rider's recent GPS pings against each official vehicle (on-device port of the backend matcher).
enum TrainMatcher {
    static let minPings = 3
    static let minConfidence = 0.6
    static let maxCandidateM = 2000.0

    static func match(pings: [Ping], vehicles: [Vehicle]) -> TrainMatch? {
        let good = pings.filter { $0.accuracyM >= 0 && $0.accuracyM <= 100 }
        guard good.count >= minPings, !vehicles.isEmpty else { return nil }

        let scored = vehicles.map { v -> (Vehicle, Double) in
            let vloc = CLLocation(latitude: v.lat, longitude: v.lon)
            var total = 0.0
            for p in good {
                let d = CLLocation(latitude: p.lat, longitude: p.lon).distance(from: vloc)
                guard d <= maxCandidateM else { continue }
                let tolerance = max(150, p.accuracyM * 2)
                var s = exp(-pow(d / tolerance, 2))
                if let h = p.heading, let b = v.bearing, (p.speedMps ?? 0) > 3 {
                    let diff = abs(h - b).truncatingRemainder(dividingBy: 360)
                    s *= min(diff, 360 - diff) < 60 ? 1 : 0.4
                }
                if let ps = p.speedMps, let vs = v.speedMps { s *= abs(ps - vs) < 8 ? 1 : 0.6 }
                total += s
            }
            return (v, total / Double(good.count))
        }.sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 > 0 else { return nil }
        let margin = best.1 - (scored.dropFirst().first?.1 ?? 0)
        let evidence = min(1, Double(good.count) / Double(minPings * 2))
        let confidence = min(1, best.1 * (0.5 + margin) * (0.5 + 0.5 * evidence))
        guard confidence >= minConfidence else { return nil }
        return TrainMatch(vehicleId: best.0.id, confidence: confidence, pings: good.count)
    }
}
