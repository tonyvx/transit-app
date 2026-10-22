import SwiftUI
import WidgetKit

struct DepartureRow: Identifiable, Sendable {
    let id: String
    let route: String
    let destination: String
    let colorHex: String?
    let time: Date
}

struct StationBoard: Identifiable, Sendable {
    let id: String
    let name: String
    let rows: [DepartureRow]
}

struct BoardEntry: TimelineEntry {
    let date: Date
    let boards: [StationBoard]
    let hasFavorites: Bool
}

/// Fetches live predictions straight from the MBTA, the same way the app does.
enum DepartureFeed {
    private struct Ref: Decodable { let id: String }
    private struct Rel: Decodable { let data: Ref? }
    private struct Rels: Decodable { let route: Rel? }
    private struct Pred: Decodable {
        struct Attrs: Decodable { let departure_time: String?; let direction_id: Int?; let schedule_relationship: String? }
        let id: String; let attributes: Attrs; let relationships: Rels?
    }
    private struct RouteRes: Decodable {
        struct Attrs: Decodable { let long_name: String?; let short_name: String?; let color: String?; let direction_destinations: [String?]? }
        let id: String; let attributes: Attrs
    }
    private struct Doc: Decodable { let data: [Pred]; let included: [RouteRes]? }

    static func board(for station: FavoriteStation, key: String) async -> StationBoard {
        var c = URLComponents(string: "https://api-v3.mbta.com/predictions")!
        c.queryItems = [
            .init(name: "filter[stop]", value: station.stopId), .init(name: "sort", value: "departure_time"),
            .init(name: "include", value: "route"), .init(name: "page[limit]", value: "30"),
        ]
        var req = URLRequest(url: c.url!)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req), let doc = try? JSONDecoder().decode(Doc.self, from: data) else {
            return StationBoard(id: station.stopId, name: station.name, rows: [])
        }
        let routes = Dictionary(uniqueKeysWithValues: (doc.included ?? []).map { ($0.id, $0.attributes) })
        let parse = ISO8601DateFormatter()
        let now = Date()
        let rows: [DepartureRow] = doc.data.compactMap { p in
            // Skip trains that only arrive here (no departure time) and cancelled or skipped stops.
            guard let t = p.attributes.departure_time.flatMap({ parse.date(from: $0) }), t > now,
                  !["SKIPPED", "CANCELLED"].contains(p.attributes.schedule_relationship ?? "") else { return nil }
            let rid = p.relationships?.route?.data?.id ?? ""
            let r = routes[rid]
            let dests = r?.direction_destinations ?? []
            let dest = p.attributes.direction_id.flatMap { $0 < dests.count ? dests[$0] : nil } ?? r?.long_name ?? rid
            let name = (r?.long_name ?? r?.short_name ?? rid).replacingOccurrences(of: " Line", with: "")
            return DepartureRow(id: p.id, route: name, destination: dest, colorHex: r?.color, time: t)
        }
        return StationBoard(id: station.stopId, name: station.name, rows: Array(rows.prefix(4)))
    }
}

struct BoardProvider: TimelineProvider {
    private var apiKey: String { Bundle.main.object(forInfoDictionaryKey: "MBTA_API_KEY") as? String ?? "" }

    func placeholder(in context: Context) -> BoardEntry {
        let now = Date()
        let rows = [("Red", "Alewife", 3), ("Red", "Braintree", 7), ("Red", "Alewife", 11)].enumerated().map {
            DepartureRow(id: "\($0.offset)", route: $0.element.0, destination: $0.element.1, colorHex: "#DA291C", time: now.addingTimeInterval(Double($0.element.2) * 60))
        }
        return BoardEntry(date: now, boards: [StationBoard(id: "p", name: "Park Street", rows: rows)], hasFavorites: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (BoardEntry) -> Void) {
        let fallback = placeholder(in: context)
        if context.isPreview { completion(fallback); return }
        Task { completion((await entries(count: 1)).first ?? fallback) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<BoardEntry>) -> Void) {
        Task {
            let e = await entries(count: 10)
            completion(Timeline(entries: e, policy: .after(Date().addingTimeInterval(10 * 60))))
        }
    }

    /// One fetch drives several entries a minute apart, so the "min" labels stay current without more network calls.
    private func entries(count: Int) async -> [BoardEntry] {
        let favs = SharedStorage.stations()
        let key = apiKey
        let boards = await withTaskGroup(of: (Int, StationBoard).self) { group in
            for (i, f) in favs.prefix(2).enumerated() { group.addTask { (i, await DepartureFeed.board(for: f, key: key)) } }
            var out: [(Int, StationBoard)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let start = Date()
        return (0..<count).map { BoardEntry(date: start.addingTimeInterval(Double($0) * 60), boards: boards, hasFavorites: !favs.isEmpty) }
    }
}

extension Color {
    init(hex: String?) {
        let v = hex.flatMap { UInt32($0.drop { $0 == "#" }, radix: 16) } ?? 0x6B6B6B
        self.init(red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255)
    }
}

private func minutes(_ t: Date, from now: Date) -> String {
    let m = Int((t.timeIntervalSince(now) / 60).rounded(.down))
    return m <= 0 ? "Now" : "\(m) min"
}

struct RowView: View {
    let row: DepartureRow
    let now: Date
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: row.colorHex)).frame(width: 8, height: 8)
            Text(row.destination).lineLimit(1).font(compact ? .caption : .footnote)
            Spacer(minLength: 4)
            Text(minutes(row.time, from: now)).font((compact ? Font.caption : .footnote).monospacedDigit().bold())
        }
    }
}

struct BoardView: View {
    let board: StationBoard
    let now: Date
    var rows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(board.name).font(.caption.bold()).lineLimit(1)
            let upcoming = board.rows.filter { $0.time > now.addingTimeInterval(-30) }
            if upcoming.isEmpty {
                Text("No upcoming trains").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(upcoming.prefix(rows)) { RowView(row: $0, now: now, compact: true) }
            }
        }
    }
}

struct EmptyFavorites: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "star").font(.title3)
            Text("Star a station in Boston Transit").font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}

struct BoardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BoardEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            if let b = entry.boards.first, let r = b.rows.first(where: { $0.time > entry.date }) {
                Text("\(b.name): \(r.destination) \(minutes(r.time, from: entry.date))")
            } else {
                Text("Boston Transit")
            }
        case .accessoryRectangular:
            if let b = entry.boards.first { BoardView(board: b, now: entry.date, rows: 2) } else { Text("Star a station in the app").font(.caption) }
        case .systemMedium:
            if entry.boards.isEmpty { EmptyFavorites() } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(entry.boards) { BoardView(board: $0, now: entry.date, rows: 4) }
                }
            }
        default:
            if let b = entry.boards.first { BoardView(board: b, now: entry.date, rows: 4) } else { EmptyFavorites() }
        }
    }
}

struct BostonTransitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextTrains", provider: BoardProvider()) { entry in
            BoardWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next trains")
        .description("Live departures at your favorite stations.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct BostonTransitWidgets: WidgetBundle {
    var body: some Widget { BostonTransitWidget() }
}
