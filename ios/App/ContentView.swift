import MapKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAlerts = false
    @State private var showPreferences = false
    @State private var selectedRouteId: String?
    @State private var showHowTo = false
    @AppStorage("hasSeenHowTo") private var hasSeenHowTo = false
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: .init(latitude: 42.3601, longitude: -71.0589),
                           span: .init(latitudeDelta: 0.6, longitudeDelta: 0.6)))

    private func routeID(near c: CLLocationCoordinate2D, tolerance: Double) -> String? {
        let k = cos(c.latitude * .pi / 180)
        var best: (id: String, d: Double)?
        for trace in model.routeTraces {
            let pts = trace.coordinates
            guard pts.count > 1 else { continue }
            for i in 1..<pts.count {
                let ax = pts[i-1].longitude * k, ay = pts[i-1].latitude
                let bx = pts[i].longitude * k, by = pts[i].latitude
                let px = c.longitude * k, py = c.latitude
                let dx = bx - ax, dy = by - ay
                let len = dx * dx + dy * dy
                let t = len == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len))
                let d = hypot(px - (ax + t * dx), py - (ay + t * dy))
                if d < best?.d ?? .infinity { best = (trace.routeId, d) }
            }
        }
        guard let best, best.d <= tolerance * k else { return nil }
        return best.id
    }

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .bottom) {
            MapReader { proxy in
            Map(position: $camera, selection: $model.selectedVehicleId) {
                UserAnnotation()
                ForEach(model.routeTraces) { trace in
                    MapPolyline(coordinates: trace.coordinates.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(trace.line.color.opacity(routeOpacity(trace)),
                            style: StrokeStyle(lineWidth: isPlannedRoute(trace.routeId) ? 5 : 3, lineCap: .round))
                    .tag("route:\(trace.routeId)")
                }
                if let it = model.planner.selected {
                    ForEach(it.legs) { leg in
                        MapPolyline(coordinates: leg.coordinates)
                            .stroke(isAccess(leg) ? Color.gray : model.routeColor(leg.routeId),
                                    style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: isAccess(leg) ? [2, 8] : []))
                    }
                }
                if let a = model.planner.from, model.planner.selected != nil {
                    Marker("A", coordinate: a.coordinate).tint(.green)
                }
                if let b = model.planner.to, model.planner.selected != nil {
                    Marker("B", coordinate: b.coordinate).tint(.red)
                }
                ForEach(model.visibleStations) { st in
                    Annotation(st.name, coordinate: .init(latitude: st.lat, longitude: st.lon), anchor: .center) {
                        Button { model.selectedStation = st } label: {
                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(st.line.color, lineWidth: 4))
                                .frame(width: 32, height: 32)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(plannedRouteIDs.isEmpty || plannedLines.contains(st.line) ? 1 : 0.2)
                        .accessibilityLabel("Station \(st.name)")
                    }
                }
                ForEach(model.mapVehicles) { v in
                    Annotation(v.label ?? v.id, coordinate: .init(latitude: v.lat, longitude: v.lon)) {
                        TrainMarker(color: color(for: v.routeId), isMine: v.id == model.myTrain?.vehicleId, isHighlighted: v.id == model.highlightedVehicleId)
                            .opacity(plannedRouteIDs.isEmpty || isPlannedRoute(v.routeId) ? 1 : 0.2)
                    }
                    .tag(v.id)
                }
            }
            .mapControls { MapUserLocationButton(); MapCompass() }
            .onTapGesture { point in
                guard let c = proxy.convert(point, from: .local) else { return }
                let edge = proxy.convert(CGPoint(x: point.x + 28, y: point.y), from: .local)
                let tolerance = edge.map { abs($0.longitude - c.longitude) } ?? 0.002
                if let id = routeID(near: c, tolerance: tolerance) {
                    selectedRouteId = id
                } else {
                    model.planner.dropPin(c)
                }
            }
            }

            VStack(spacing: 8) {
                HStack {
                    emptyStateHint
                    Spacer(minLength: 0)
                    Button { showPreferences = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("Boston Transit settings")
                    .accessibilityIdentifier("moreButton")
                }
                if let m = model.myTrain, let v = model.vehicles.first(where: { $0.id == m.vehicleId }) {
                    MyTrainCard(vehicle: v, match: m)
                }
                if let v = model.selected { VehicleCard(vehicle: v) }
            }
            .padding()
        }
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                statusBar
                plannerSummaryBar
                journeyStatusBar
            }
            .padding(.horizontal)
        }
        .overlay(alignment: .top) {
            if let f = model.planner.pickTarget {
                HStack {
                    Text("Tap the map to set \(f == .from ? "start" : "destination")")
                    Button("Cancel") { model.planner.pickTarget = nil; model.planner.showSheet = true }
                }
                .padding(10).background(.thinMaterial, in: Capsule()).padding(.top, 40)
            }
        }
        .sheet(isPresented: Binding(get: { model.planner.showSheet }, set: { model.planner.showSheet = $0 })) {
            PlannerView()
                .presentationDetents([.medium, .large])
        }
        .onChange(of: model.planner.selectedId) { _, _ in fitItinerary() }
        .onChange(of: model.planner.results.count) { _, _ in fitItinerary() }
        .task { await model.refreshLoop() }
        .onChange(of: scenePhase) { _, phase in model.isActive = phase == .active }
        .sheet(isPresented: $showAlerts) { AlertsView() }
        .sheet(item: $model.selectedStation) { st in
            StationSheet(station: st) { vehicleId in
                model.highlight(vehicleId: vehicleId)
                model.selectedStation = nil
            }
            .presentationDetents([.medium, .large])
        }
        .task(id: model.stationRequestKey) { await model.loadStations() }
        .onChange(of: model.highlightedVehicleId) { _, id in
            guard let id, let v = model.vehicles.first(where: { $0.id == id }) else { return }
            withAnimation {
                camera = .region(MKCoordinateRegion(center: .init(latitude: v.lat, longitude: v.lon),
                                                    span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)))
            }
        }
        .onChange(of: model.selectedVehicleId) { _, id in
            if let id, id.hasPrefix("route:") {
                selectedRouteId = String(id.dropFirst("route:".count))
                model.selectedVehicleId = nil
                return
            }
            if id != model.highlightedVehicleId { model.highlightedVehicleId = nil }
        }
        .sheet(isPresented: $showPreferences) { PreferencesView() }
        .sheet(item: Binding(
            get: { selectedRouteId.flatMap { model.routes[$0] } },
            set: { selectedRouteId = $0?.id }
        )) { route in
            RouteDetailView(
                route: route,
                color: model.routeColor(route.id),
                directions: model.routeDirections.filter { $0.routeId == route.id },
                isFavorite: model.isFavoriteRoute(route.id),
                toggleFavorite: { model.toggleFavoriteRoute(route.id) }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showHowTo, onDismiss: { model.location.start() }) { HowToView() }
        .alert(
            "Are you on this train?",
            isPresented: Binding(
                get: { model.journey.pendingSuggestion != nil },
                set: { if !$0 { model.journey.dismissSuggestion() } }
            ),
            presenting: model.journey.pendingSuggestion
        ) { suggestion in
            Button("I'm on \(suggestion.trainLabel)") {
                Task {
                    await model.journey.confirmSuggestion(
                        itinerary: model.planner.selected,
                        location: model.location,
                        routeNames: model.routes.mapValues(\.name)
                    )
                }
            }
            Button("Not now", role: .cancel) { model.journey.dismissSuggestion() }
        } message: { suggestion in
            Text("GPS matches the planned \(suggestion.routeName) train from \(suggestion.boardName) to \(suggestion.destinationName). Confirm to show your next stop and stops remaining on the Lock Screen. Your location stays on this iPhone.")
        }
        .task {
            // Ask for location after the first-run guide, so the two don't stack.
            if hasSeenHowTo { model.location.start() } else { hasSeenHowTo = true; showHowTo = true }
        }
    }

    private var plannedRouteIDs: Set<String> {
        Set(model.planner.selected?.transitLegs.compactMap(\.routeId) ?? [])
    }

    private var plannedLines: Set<LineGroup> {
        Set(plannedRouteIDs.compactMap { routeId in
            model.routes[routeId].flatMap { LineGroup(routeId: $0.id) }
        })
    }

    private func isPlannedRoute(_ routeId: String) -> Bool {
        plannedRouteIDs.contains(routeId)
    }

    private func routeOpacity(_ trace: RouteTrace) -> Double {
        guard !plannedRouteIDs.isEmpty else {
            return model.preferences.lines.contains(trace.line) ? 0.9 : 0.35
        }
        return isPlannedRoute(trace.routeId) ? 0.95 : 0.16
    }

    private var statusBar: some View {
        Group {
            if model.isOffline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                    if let t = model.fetchedAt {
                        Text("No connection · showing trains from \(t, style: .time)")
                    } else {
                        Text("No connection · can't load trains")
                    }
                }
                .font(.caption.weight(.medium))
                .padding(8)
                .background(.orange.opacity(0.9), in: Capsule())
                .foregroundStyle(.white)
                .accessibilityIdentifier("offlineBanner")
            } else if let e = model.routeMapError {
                HStack(spacing: 8) {
                    Text(e).font(.caption.weight(.medium))
                    Button("Retry") { Task { await model.loadRouteTraces() } }
                        .font(.caption.bold())
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                .padding(8)
                .background(.red.opacity(0.9), in: Capsule())
                .foregroundStyle(.white)
            } else if let t = model.fetchedAt {
                Text("Updated \(t, style: .time)").font(.caption).padding(6).background(.regularMaterial, in: Capsule())
            }
        }
        .padding(.top, 4)
    }

    /// Guides a new rider, or explains an empty map.
    @ViewBuilder
    private var emptyStateHint: some View {
        if model.preferences.lines.isEmpty {
            hint("Tap a route on the map to follow it", icon: "hand.tap")
        } else if model.fetchedAt != nil, !model.isOffline, model.visibleVehicles.isEmpty {
            hint(model.preferences.onlyApproaching
                 ? "No trains approaching you on your lines"
                 : "No trains running on your lines right now",
                 icon: "moon.zzz")
        }
    }

    private func hint(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .accessibilityIdentifier("emptyStateHint")
    }

    private var plannerSummaryBar: some View {
        HStack(spacing: 8) {
            Button { model.planner.showSheet = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.planner.selected == nil ? "arrow.triangle.turn.up.right.diamond.fill" : "tram.fill")
                        .foregroundStyle(Color.accentColor)
                    if let itinerary = model.planner.selected,
                       let from = model.planner.from,
                       let to = model.planner.to {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(from.name) → \(to.name)")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("Leave \(itinerary.leaveBy, style: .time) · arrive \(itinerary.arriveAt, style: .time) · \(transferSummary(itinerary.transfers))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Plan a trip")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plannerSummaryButton")
            .frame(maxWidth: .infinity)

            Button { showAlerts = true } label: {
                Label("\(model.alerts.count)", systemImage: "exclamationmark.triangle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("\(model.alerts.count) alerts")
            .accessibilityIdentifier("alertsButton")
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var journeyStatusBar: some View {
        if model.journey.isActive {
            HStack(spacing: 8) {
                Image(systemName: "tram.fill").foregroundStyle(Color.accentColor)
                Text("\(model.journey.nextStopName) · \(model.journey.stopsRemaining) stops to go")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button("End") {
                    Task { await model.journey.endTrip(location: model.location) }
                }
                .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
        } else if let message = model.journey.statusMessage {
            Text(message)
                .font(.caption)
                .padding(8)
                .background(.regularMaterial, in: Capsule())
        }
    }

    private func transferSummary(_ count: Int) -> String {
        switch count {
        case 0: "Direct"
        case 1: "1 transfer"
        default: "\(count) transfers"
        }
    }

    private func isAccess(_ leg: ItineraryLeg) -> Bool {
        if case .transit = leg.kind { false } else { true }
    }

    private func fitItinerary() {
        guard let it = model.planner.selected else { return }
        let pts = it.legs.flatMap(\.coordinates)
        guard let minLat = pts.map(\.latitude).min(), let maxLat = pts.map(\.latitude).max(),
              let minLon = pts.map(\.longitude).min(), let maxLon = pts.map(\.longitude).max() else { return }
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                span: .init(latitudeDelta: max(0.02, (maxLat - minLat) * 1.5), longitudeDelta: max(0.02, (maxLon - minLon) * 1.5))))
        }
    }

    private func color(for routeId: String) -> Color {
        if let hex = model.routes[routeId]?.color, let v = UInt32(hex.dropFirst(), radix: 16) {
            return Color(red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255)
        }
        return .purple
    }
}

struct MyTrainCard: View {
    @Environment(AppModel.self) private var model
    let vehicle: Vehicle
    let match: TrainMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You're probably on train \(vehicle.label ?? vehicle.id)").font(.headline)
            Text("\(model.routes[vehicle.routeId]?.name ?? vehicle.routeId) · \(Confidence(match.confidence).label) confidence")
                .font(.subheadline)
            if let d = vehicle.updatedAt { Text("Official update: \(d, style: .relative) ago").font(.caption) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct VehicleCard: View {
    private static func statusText(_ raw: String?) -> String {
        switch raw {
        case "STOPPED_AT": "Stopped at station"
        case "INCOMING_AT": "Arriving at next stop"
        case "IN_TRANSIT_TO": "In transit to next stop"
        default: raw?.replacingOccurrences(of: "_", with: " ").capitalized ?? ""
        }
    }

    @Environment(AppModel.self) private var model
    let vehicle: Vehicle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.routes[vehicle.routeId]?.name ?? vehicle.routeId).font(.headline)
            Text("Train \(vehicle.label ?? vehicle.id) · \(Self.statusText(vehicle.status))")
                .font(.subheadline)
            if let d = vehicle.updatedAt { Text("Official update: \(d, style: .relative) ago").font(.caption) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct AlertsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showOther = false

    var body: some View {
        let g = model.alertGroups
        let inbound = g.mine.filter { $0.directionIds == [Direction.inbound.rawValue] }
        let outbound = g.mine.filter { $0.directionIds == [Direction.outbound.rawValue] }
        let both = g.mine.filter { $0.directionIds != [Direction.inbound.rawValue] && $0.directionIds != [Direction.outbound.rawValue] }
        let other = g.ahead + g.other
        NavigationStack {
            List {
                if !inbound.isEmpty {
                    Section("Inbound") { ForEach(inbound) { AlertRow(alert: $0) } }
                }
                if !outbound.isEmpty {
                    Section("Outbound") { ForEach(outbound) { AlertRow(alert: $0) } }
                }
                if !both.isEmpty {
                    Section("Both directions") { ForEach(both) { AlertRow(alert: $0) } }
                }
                if g.mine.isEmpty {
                    Section {
                        Text(model.preferences.lines.isEmpty
                             ? "Favorite a line to see its alerts here."
                             : "No alerts on your favorite lines.")
                            .foregroundStyle(.secondary)
                    }
                }
                if !other.isEmpty {
                    Section {
                        DisclosureGroup("Other lines (\(other.count))", isExpanded: $showOther) {
                            ForEach(other) { AlertRow(alert: $0) }
                        }
                    }
                }
            }
            .overlay { if model.alerts.isEmpty { Text("No MBTA alerts").foregroundStyle(.secondary) } }
            .navigationTitle("MBTA Alerts")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct AlertRow: View {
    @Environment(AppModel.self) private var model
    let alert: TransitAlert

    private var color: Color {
        if let id = alert.routeIds.first(where: { LineGroup(routeId: $0) != nil }) {
            if model.routes[id]?.color != nil { return model.routeColor(id) }
            if let line = LineGroup(routeId: id) { return line.color }
        }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alert.effect.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(alert.header)
            if let start = model.nearbyStart(for: alert) {
                Label(driveText(start), systemImage: "car.fill").font(.caption.bold()).foregroundStyle(.blue)
            }
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
        }
        .listRowBackground(color.opacity(0.12))
    }

    private func driveText(_ s: NearbyStart) -> String {
        guard let secs = s.driveSeconds else { return "\(s.stationName) is where this line starts" }
        let mins = max(1, Int((secs / 60).rounded()))
        return "\(mins) min drive to \(s.stationName), where this line starts"
    }
}

extension LineGroup {
    var color: Color {
        switch self {
        case .commuter: Color(red: 0.67, green: 0.18, blue: 0.64)
        case .red: Color(red: 0.85, green: 0.16, blue: 0.11)
        case .green: Color(red: 0, green: 0.52, blue: 0.24)
        case .blue: Color(red: 0, green: 0.24, blue: 0.65)
        case .orange: Color(red: 0.93, green: 0.55, blue: 0)
        case .silver: Color(red: 0.49, green: 0.53, blue: 0.56)
        }
    }
}

struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Preferences()
    @State private var showTerms = false

    var body: some View {
        NavigationStack {
            List {
                Section("Feedback") {
                    if let url = feedbackURL(
                        subject: "Boston Transit bug report",
                        body: "What happened?\n\nWhat did you expect?\n\nSteps to reproduce:\n\nPlease avoid including personal or precise location information."
                    ) {
                        Link(destination: url) {
                            Label("Report a bug", systemImage: "ladybug")
                        }
                        .accessibilityIdentifier("reportBugLink")
                    }
                    if let url = feedbackURL(
                        subject: "Boston Transit feature request",
                        body: "What would you like the app to do?\n\nHow would it help your transit trip?\n\nPlease avoid including personal or precise location information."
                    ) {
                        Link(destination: url) {
                            Label("Request a feature", systemImage: "lightbulb")
                        }
                        .accessibilityIdentifier("requestFeatureLink")
                    }
                    Text("Opens your email app to send feedback to valantra.app@gmail.com.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Terms & Policy") {
                    Button {
                        showTerms = true
                    } label: {
                        Label("Terms and privacy", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("termsPrivacyButton")
                }
                Section("How to use") {
                    NavigationLink {
                        HowToView(embedded: true)
                    } label: {
                        Label("Open the guide", systemImage: "book")
                    }
                    .accessibilityIdentifier("openGuideLink")
                    Text("Plan trips, read alerts, and choose routes directly on the map.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Trip tracking") {
                    Toggle(isOn: Binding(
                        get: { model.location.backgroundTripTrackingEnabled },
                        set: { model.location.setBackgroundTripTracking($0) }
                    )) {
                        Label("Allow background trip updates", systemImage: "location.circle")
                    }
                    if model.location.authorization == .denied || model.location.authorization == .restricted {
                        Text("Location access is disabled. Change it in Settings > Privacy & Security > Location Services > Boston Transit.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if model.location.backgroundTripTrackingEnabled,
                              model.location.authorization != .authorizedAlways {
                        Text("Choose Always in the iOS location permission prompt or Settings. Background GPS is used only during a confirmed trip to update its Lock Screen Live Activity.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("When enabled, GPS and MBTA train positions are compared on this iPhone during a confirmed trip. The Live Activity shows your next stop and stops remaining. No location is sent to a server.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if model.favorites.stations.isEmpty {
                        Text("Tap a station on the map, then the star, to add it here and to the home-screen widget.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(model.favorites.stations) { Label($0.name, systemImage: "star.fill").foregroundStyle(.primary) }
                        .onDelete { model.favorites.removeStations(at: $0) }
                        .onMove { model.favorites.moveStation(from: $0, to: $1) }
                } header: {
                    HStack { Text("Favorite stations"); Spacer(); if !model.favorites.stations.isEmpty { EditButton().font(.footnote) } }
                } footer: {
                    Text("The widget shows the next trains at your first two favorites.")
                }
                Section("Favorite lines") {
                    if model.favoriteLineGroups.isEmpty {
                        Text("No favorite lines yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(model.favoriteLineGroups) { line in
                                    Text(line.rawValue)
                                        .font(.footnote.bold())
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(line.color, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    NavigationLink {
                        FavoriteLinesEditor()
                    } label: {
                        Label("Edit favorite lines", systemImage: "star")
                    }
                    .accessibilityIdentifier("editFavoriteLinesLink")
                }
                Section("Directions") {
                    ForEach(Direction.allCases) { d in Toggle(d.label, isOn: binding(d)) }
                    Text("With no direction selected, both directions are shown.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Only trains that haven't passed me", isOn: $draft.onlyApproaching)
                } footer: {
                    Text("Uses your location and the next stop predictions at your nearest station on each line. Direction selection above still applies.")
                }
                Section("General MBTA Information & Support") {
                    officialLink("MBTA website", icon: "tram", url: "https://www.mbta.com")
                    officialLink("Service alerts", icon: "exclamationmark.triangle", url: "https://www.mbta.com/alerts")
                    officialLink("Fares and passes", icon: "ticket", url: "https://www.mbta.com/fares")
                    officialLink("Accessibility", icon: "accessibility", url: "https://www.mbta.com/accessibility")
                    officialLink("Contact MBTA support", icon: "questionmark.circle", url: "https://www.mbta.com/customer-support")
                    officialLink("Developer information", icon: "curlybraces", url: "https://www.mbta.com/developers")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Boston Transit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    // Favorite lines save immediately in their editor, so keep those rather than the draft's copy.
                    var saved = draft
                    saved.lines = model.preferences.lines
                    saved.routes = model.preferences.routes
                    model.savePreferences(saved)
                    dismiss()
                } }
            }
            .onAppear { draft = model.preferences }
            .sheet(isPresented: $showTerms) {
                TermsPrivacyView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func feedbackURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "valantra.app@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    @ViewBuilder
    private func officialLink(_ title: String, icon: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                Label(title, systemImage: icon)
            }
        }
    }

    private func binding(_ d: Direction) -> Binding<Bool> {
        Binding(get: { draft.directions.contains(d) },
                set: { if $0 { draft.directions.insert(d) } else { draft.directions.remove(d) } })
    }
}

struct TrainMarker: View {
    let color: Color
    let isMine: Bool
    let isHighlighted: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isHighlighted {
                Circle()
                    .fill(.yellow.opacity(0.35))
                    .frame(width: 56, height: 56)
                    .scaleEffect(pulse ? 1.25 : 0.8)
                    .overlay(Circle().strokeBorder(.yellow, lineWidth: 3).frame(width: 56, height: 56).scaleEffect(pulse ? 1.25 : 0.8))
                    .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
            }
            Image(systemName: "tram.fill")
                .padding(6)
                .background(color, in: Circle())
                .overlay { if isMine { Circle().strokeBorder(.yellow, lineWidth: 3) } }
                .foregroundStyle(.white)
        }
    }
}

struct StationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let station: Station
    let onSelectTrain: (String) -> Void
    @State private var arrivals: [Arrival]?

    var body: some View {
        NavigationStack {
            Group {
                if let arrivals {
                    if arrivals.isEmpty {
                        Text("No upcoming trains").foregroundStyle(.secondary)
                    } else {
                        List(arrivals) { a in row(a) }
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(station.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    let fav = model.favorites.isFavorite(station.stopId)
                    Button { model.favorites.toggleStation(stopId: station.stopId, name: station.name) } label: {
                        Image(systemName: fav ? "star.fill" : "star").foregroundStyle(fav ? .yellow : .accentColor)
                    }
                    .accessibilityLabel(fav ? "Remove from favorites" : "Add to favorites")
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .task {
            // Refresh while the sheet is open.
            while !Task.isCancelled {
                arrivals = await model.arrivals(at: station)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func row(_ a: Arrival) -> some View {
        HStack {
            if let vid = a.vehicleId {
                Button { onSelectTrain(vid) } label: {
                    Label("Train \(model.trainLabel(vid))", systemImage: "tram.fill")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(station.line.color, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                Text("Train not assigned yet").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(model.routes[a.routeId]?.name ?? a.routeId).font(.caption).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing) {
                Text(a.time, style: .time).font(.headline)
                Text(a.time, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
