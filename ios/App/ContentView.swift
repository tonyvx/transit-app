import MapKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showAlerts = false
    @State private var showPreferences = false
    @State private var showHelpAndFeedback = false
    @State private var showHowTo = false
    @AppStorage("hasSeenHowTo") private var hasSeenHowTo = false
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: .init(latitude: 42.3601, longitude: -71.0589),
                           span: .init(latitudeDelta: 0.6, longitudeDelta: 0.6)))

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .bottom) {
            MapReader { proxy in
            Map(position: $camera, selection: $model.selectedVehicleId) {
                UserAnnotation()
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
                        .accessibilityLabel("Station \(st.name)")
                    }
                }
                ForEach(model.mapVehicles) { v in
                    Annotation(v.label ?? v.id, coordinate: .init(latitude: v.lat, longitude: v.lon)) {
                        TrainMarker(color: color(for: v.routeId), isMine: v.id == model.myTrain?.vehicleId, isHighlighted: v.id == model.highlightedVehicleId)
                    }
                    .tag(v.id)
                }
            }
            .mapControls { MapUserLocationButton(); MapCompass() }
            .onTapGesture { point in
                if let c = proxy.convert(point, from: .local) { model.planner.dropPin(c) }
            }
            }

            VStack(spacing: 8) {
                if model.preferences.lines.isEmpty { FirstRunCard { showHowTo = true } }
                LegendView(
                    onPreferences: { showPreferences = true },
                    onAlerts: { showAlerts = true },
                    onHelp: { showHelpAndFeedback = true }
                )
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
            if id != model.highlightedVehicleId { model.highlightedVehicleId = nil }
        }
        .sheet(isPresented: $showPreferences) { PreferencesView() }
        .sheet(isPresented: $showHelpAndFeedback) { HelpAndFeedbackView() }
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

    private var statusBar: some View {
        Group {
            if let e = model.error {
                Text(e).foregroundStyle(.white).padding(6).background(.red, in: Capsule())
            } else if let t = model.fetchedAt {
                Text("Updated \(t, style: .time)").font(.caption).padding(6).background(.regularMaterial, in: Capsule())
            }
        }
        .padding(.top, 4)
    }

    private var plannerSummaryBar: some View {
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
        NavigationStack {
            List {
                if !g.mine.isEmpty {
                    Section("My lines") { ForEach(g.mine) { AlertRow(alert: $0) } }
                }
                if !g.ahead.isEmpty {
                    Section("Starting ahead of you") { ForEach(g.ahead) { AlertRow(alert: $0) } }
                }
                if !g.other.isEmpty {
                    Section {
                        DisclosureGroup("Other lines (\(g.other.count))", isExpanded: $showOther) {
                            ForEach(g.other) { AlertRow(alert: $0) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alert.effect.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
            Text(alert.header)
            if let start = model.nearbyStart(for: alert) {
                Label(driveText(start), systemImage: "car.fill").font(.caption.bold()).foregroundStyle(.blue)
            }
        }
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

struct LegendView: View {
    @Environment(AppModel.self) private var model
    let onPreferences: () -> Void
    let onAlerts: () -> Void
    let onHelp: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.chipLines) { line in
                        let on = model.enabledLines.contains(line)
                        Button { model.toggle(line) } label: {
                            Text(line.rawValue)
                                .font(.footnote.bold())
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(on ? line.color : Color.clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(line.color, lineWidth: 2))
                                .foregroundStyle(on ? .white : line.color)
                        }
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Button(action: onPreferences) { Image(systemName: "gearshape.fill") }
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityLabel("Preferences")
                .accessibilityIdentifier("preferencesButton")
            Button(action: onHelp) { Image(systemName: "questionmark.circle") }
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityLabel("Help and feedback")
                .accessibilityIdentifier("helpAndFeedbackButton")
            Button(action: onAlerts) {
                Label("\(model.alerts.count)", systemImage: "exclamationmark.triangle.fill")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .accessibilityLabel("\(model.alerts.count) alerts")
            .accessibilityIdentifier("alertsButton")
            }
            HStack(spacing: 8) {
                ForEach(Direction.allCases) { d in
                    let on = model.enabledDirections.contains(d)
                    Button { model.toggle(d) } label: {
                        Label(d.label, systemImage: d == .inbound ? "arrow.down.left" : "arrow.up.right")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(on ? Color.accentColor : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5))
                            .foregroundStyle(on ? .white : Color.accentColor)
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Spacer()
                if model.chipLines.isEmpty {
                    Text("Choose lines in preferences").font(.caption).foregroundStyle(.secondary)
                } else if model.enabledLines.isEmpty {
                    Text("Select a line").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(model.visibleVehicles.isEmpty && model.preferences.onlyApproaching
                         ? "No trains approaching you"
                         : "\(model.visibleVehicles.count) shown")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Preferences()

    var body: some View {
        NavigationStack {
            Form {
                ForEach(LineGroup.allCases) { line in
                    Section {
                        Toggle(isOn: binding(line)) {
                            Label(line.rawValue, systemImage: "circle.fill").foregroundStyle(line.color).font(.headline)
                        }
                        if draft.lines.contains(line) {
                            let routes = model.routes(in: line)
                            ForEach(routes) { r in
                                Toggle(r.name, isOn: routeBinding(r.id)).padding(.leading, 24)
                                ForEach(model.branches(for: r.id)) { b in
                                    Toggle(b.name, isOn: routeBinding(b.id)).padding(.leading, 48)
                                }
                            }
                            if routes.isEmpty {
                                Text("Loading routes…").font(.footnote).foregroundStyle(.secondary).padding(.leading, 24)
                            }
                        }
                    } header: {
                        if line == LineGroup.allCases.first { Text("Lines and routes") }
                    } footer: {
                        if draft.lines.contains(line) { Text("Select specific routes or branches to show only those. None selected shows every \(line.rawValue) route.") }
                    }
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
            }
            .navigationTitle("My Preferences")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { model.savePreferences(draft); dismiss() } }
            }
            .onAppear { draft = model.preferences }
        }
    }

    private func binding(_ line: LineGroup) -> Binding<Bool> {
        Binding(get: { draft.lines.contains(line) },
                set: { if $0 { draft.lines.insert(line) } else { draft.lines.remove(line) } })
    }

    private func routeBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { draft.routes.contains(id) },
                set: { if $0 { draft.routes.insert(id) } else { draft.routes.remove(id) } })
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
