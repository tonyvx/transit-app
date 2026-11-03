import MapKit
import SwiftUI

struct PlannerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var planner = model.planner
        NavigationStack {
            Form {
                if !model.favorites.trips.isEmpty {
                    Section("Saved trips") {
                        ForEach(model.favorites.trips) { trip in SavedTripRow(trip: trip) }
                    }
                }
                endpoint("From", field: .from, text: $planner.fromText, mode: $planner.fromMode, point: planner.from, planner: planner)
                endpoint("To", field: .to, text: $planner.toText, mode: $planner.toMode, point: planner.to, planner: planner)
                Section {
                    Picker("When", selection: $planner.timeMode) {
                        ForEach(PlannerModel.TimeMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if planner.timeMode != .now {
                        DatePicker(planner.timeMode == .arrive ? "Arrive by" : "Depart at", selection: $planner.departAt)
                    }
                    if let e = planner.error { Text(e).foregroundStyle(.red).font(.callout) }
                }
                if !planner.results.isEmpty {
                    Section("Trips") {
                        Button { if let t = planner.savedTrip() { model.favorites.save(t) } } label: { Label("Save this trip", systemImage: "star") }
                            .disabled(planner.savedTrip().map { t in model.favorites.trips.contains { $0.fromLat == t.fromLat && $0.toLat == t.toLat && $0.fromLon == t.fromLon && $0.toLon == t.toLon } } ?? true)
                        ForEach(planner.results) { it in
                            ItineraryCard(itinerary: it, selected: it.id == planner.selected?.id)
                                .contentShape(Rectangle())
                                .onTapGesture { planner.selectedId = it.id }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        planner.swap()
                    } label: {
                        Label("Swap", systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("swapTripButton")

                    Button {
                        Task { await planner.plan() }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Find trips")
                            if planner.isPlanning { ProgressView().padding(.leading, 4) }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(planner.isPlanning || planner.from == nil || planner.to == nil)
                    .accessibilityIdentifier("findTripsButton")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .refreshable { if planner.from != nil, planner.to != nil { await planner.plan() } }
            .navigationTitle("Trip planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", systemImage: "xmark.circle") { planner.clear() }
                        .disabled(!planner.hasPlanContent)
                        .accessibilityIdentifier("clearTripButton")
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func endpoint(_ title: String, field: PlanField, text: Binding<String>, mode: Binding<AccessMode>, point: PlanPoint?, planner: PlannerModel) -> some View {
        Section(title) {
            HStack {
                TextField("Address or place", text: text)
                    .submitLabel(.search)
                    .onSubmit { Task { await planner.search(field) } }
                Button { planner.useMyLocation(field) } label: { Image(systemName: "location.fill") }
                    .buttonStyle(.borderless).accessibilityLabel("Use my location")
                Button {
                    planner.pickTarget = field
                    planner.showSheet = false
                } label: { Image(systemName: "mappin.and.ellipse") }
                    .buttonStyle(.borderless).accessibilityLabel("Drop a pin on the map")
            }
            if !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               point?.name != text.wrappedValue {
                Button {
                    Task { await planner.search(field) }
                } label: {
                    Label("Search this location", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier(field == .from ? "searchFromLocationButton" : "searchToLocationButton")
            }
            if let point, point.name != text.wrappedValue { Label(point.name, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
            Picker(field == .from ? "Get to the station by" : "Get from the station by", selection: mode) {
                ForEach(AccessMode.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
            }
        }
    }
}

struct ItineraryCard: View {
    @Environment(AppModel.self) private var model
    let itinerary: Itinerary
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(Int(itinerary.duration / 60)) min").font(.headline)
                if itinerary.isLive { Label("Live", systemImage: "dot.radiowaves.left.and.right").font(.caption2).foregroundStyle(.green) }
                Spacer()
                Text("Leave \(itinerary.leaveBy, style: .time) · arrive \(itinerary.arriveAt, style: .time)").font(.caption)
            }
            Text(itinerary.transfers == 0 ? "Direct" : "\(itinerary.transfers) transfer\(itinerary.transfers > 1 ? "s" : "")")
                .font(.caption).foregroundStyle(.secondary)
            if selected {
                ReminderRow(itinerary: itinerary)
                ForEach(itinerary.legs) { leg in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(leg)).foregroundStyle(model.routeColor(leg.routeId)).frame(width: 20)
                        VStack(alignment: .leading) {
                            Text(title(leg)).font(.subheadline)
                            Text("\(leg.start, style: .time) – \(leg.end, style: .time)").font(.caption).foregroundStyle(.secondary)
                            if let note = status(leg) { Text(note.text).font(.caption2).foregroundStyle(note.color) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(selected ? Color.accentColor.opacity(0.12) : nil)
    }

    private func status(_ leg: ItineraryLeg) -> (text: String, color: Color)? {
        guard case .transit = leg.kind else { return nil }
        guard leg.isLive else { return ("Scheduled time", .secondary) }
        let mins = Int((Double(leg.delaySeconds) / 60).rounded())
        if mins >= 2 { return ("Live · \(mins) min late", .orange) }
        if mins <= -2 { return ("Live · \(-mins) min early", .green) }
        return ("Live · on time", .green)
    }

    private func icon(_ leg: ItineraryLeg) -> String {
        switch leg.kind {
        case .access(let m): m.icon
        case .transfer: "figure.walk"
        case .transit: "tram.fill"
        }
    }

    private func title(_ leg: ItineraryLeg) -> String {
        switch leg.kind {
        case .access(let m): "\(m.label) \(leg.fromName) → \(leg.toName)"
        case .transfer: "Transfer to \(leg.toName)"
        case .transit: "\(model.routes[leg.routeId ?? ""]?.name ?? leg.routeId ?? "") \(leg.fromName) → \(leg.toName) (\(leg.stopCount) stops)"
        }
    }
}

struct SavedTripRow: View {
    @Environment(AppModel.self) private var model
    let trip: SavedTrip
    @State private var alertMessage: String?

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                let m = trip.reminderMinutes ?? 8 * 60
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                let minutes = (c.hour ?? 8) * 60 + (c.minute ?? 0)
                Task { if await !model.favorites.setReminder(trip, minutes: minutes) { alertMessage = "Allow notifications in Settings to get reminders." } }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { model.planner.load(trip); Task { await model.planner.plan() } } label: {
                    VStack(alignment: .leading) {
                        Text(trip.name).font(.subheadline.bold())
                        Text("Tap to plan from now").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button(role: .destructive) { model.favorites.remove(trip) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).accessibilityLabel("Delete saved trip")
            }
            Toggle("Weekday reminder", isOn: Binding(
                get: { trip.reminderMinutes != nil },
                set: { on in Task { if await !model.favorites.setReminder(trip, minutes: on ? 8 * 60 : nil) { alertMessage = "Allow notifications in Settings to get reminders." } } }))
                .font(.caption)
            if trip.reminderMinutes != nil {
                DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute).font(.caption)
            }
            if let alertMessage { Text(alertMessage).font(.caption).foregroundStyle(.red) }
        }
    }
}

/// "Remind me to leave" for one itinerary.
struct ReminderRow: View {
    let itinerary: Itinerary
    @Environment(AppModel.self) private var model
    @State private var minutesBefore = 10
    @State private var scheduled = false
    @State private var message: String?

    private var key: String { "\(Int(itinerary.leaveBy.timeIntervalSince1970))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    Task {
                        if scheduled {
                            Notifier.cancelLeaveReminder(key: key)
                            scheduled = false
                            message = nil
                        } else {
                            let dest = model.planner.to?.name ?? "your destination"
                            scheduled = await Notifier.scheduleLeaveReminder(key: key, leaveBy: itinerary.leaveBy, minutesBefore: minutesBefore, destination: dest)
                            message = scheduled ? nil : "Couldn't set it. That time has passed, or notifications are off in Settings."
                        }
                    }
                } label: { Label(scheduled ? "Reminder set" : "Remind me to leave", systemImage: scheduled ? "bell.fill" : "bell") }
                    .buttonStyle(.borderless).font(.subheadline)
                Spacer()
                Picker("", selection: $minutesBefore) {
                    Text("At leave time").tag(0)
                    Text("5 min before").tag(5)
                    Text("10 min before").tag(10)
                    Text("15 min before").tag(15)
                }
                .labelsHidden().disabled(scheduled)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
        }
        .task(id: key) { scheduled = await Notifier.hasLeaveReminder(key: key) }
    }
}
