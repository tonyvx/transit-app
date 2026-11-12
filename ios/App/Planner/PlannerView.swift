import MapKit
import SwiftUI

struct PlannerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: PlanField?
    @State private var savedTripsExpanded = false

    var body: some View {
        @Bindable var planner = model.planner
        NavigationStack {
            Form {
                Section {
                    DisclosureGroup(isExpanded: $savedTripsExpanded) {
                        if model.favorites.trips.isEmpty {
                            Text("No saved trips yet").foregroundStyle(.secondary)
                        } else {
                            ForEach(model.favorites.trips) { trip in SavedTripRow(trip: trip) }
                        }
                    } label: {
                        Text("Saved trips (\(model.favorites.trips.count))")
                    }
                    .accessibilityIdentifier("savedTripsDisclosure")
                }
                Section {
                    HStack(spacing: 0) {
                        ForEach([AccessMode.walk, .car, .scooter, .bike]) { mode in
                            Button {
                                focusedField = nil
                                planner.setModeForBoth(mode)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: mode.icon)
                                    Text(mode.label).font(.caption)
                                }
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(planner.fromMode == mode && planner.toMode == mode ? Color.accentColor.opacity(0.16) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use \(mode.label) for both station legs")
                            .accessibilityIdentifier("stationMode-\(mode.rawValue)")
                            .accessibilityAddTraits(planner.fromMode == mode && planner.toMode == mode ? .isSelected : [])
                        }
                    }
                }
                Section {
                    endpoint(field: .from, text: planner.fromText, mode: $planner.fromMode, point: planner.from, planner: planner)
                    endpoint(field: .to, text: planner.toText, mode: $planner.toMode, point: planner.to, planner: planner)
                    lookupFeedback(field: .from, text: planner.fromText, point: planner.from, planner: planner)
                    lookupFeedback(field: .to, text: planner.toText, point: planner.to, planner: planner)
                }
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
            .scrollDismissesKeyboard(.immediately)
            .background {
                Color.clear.contentShape(Rectangle()).onTapGesture { focusedField = nil }
            }
            .onChange(of: savedTripsExpanded) { _, _ in focusedField = nil }
            .onChange(of: planner.timeMode) { _, _ in focusedField = nil }
            .onChange(of: focusedField) { oldField, newField in
                if let oldField, oldField != newField {
                    Task { await planner.search(oldField) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        focusedField = nil
                        planner.swap()
                    } label: {
                        Label("Swap", systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("swapTripButton")

                    Spacer()

                    Button {
                        focusedField = nil
                        Task { await planner.resolveAndPlan() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("GO").bold()
                            if planner.isPlanning || planner.isResolving { ProgressView().padding(.leading, 4) }
                        }
                        .frame(minWidth: 54, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(planner.isPlanning || planner.isResolving ||
                              planner.fromText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              planner.toText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func endpoint(field: PlanField, text: String, mode: Binding<AccessMode>, point: PlanPoint?, planner: PlannerModel) -> some View {
        Group {
            HStack(spacing: 2) {
                Image(systemName: field == .from ? "location.fill" : "mappin")
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(field == .from ? Color.blue : Color.red, in: Circle())
                    .padding(.trailing, 6)
                    .accessibilityHidden(true)
                TextField("Address or place", text: Binding(get: { text }, set: { planner.updateText($0, field: field) }))
                    .focused($focusedField, equals: field)
                    .accessibilityLabel(field == .from ? "Start address or place" : "Destination address or place")
                    .accessibilityIdentifier(field == .from ? "fromAddressField" : "toAddressField")
                    .submitLabel(.search)
                    .onSubmit { focusedField = nil; Task { await planner.search(field) } }
                Button {
                    focusedField = nil
                    planner.useMyLocation(field)
                } label: {
                    Image(systemName: "location.fill").frame(width: 40, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(field == .from ? "Use my location for start" : "Use my location for destination")
                .accessibilityIdentifier(field == .from ? "fromCurrentLocationButton" : "toCurrentLocationButton")
                Button {
                    focusedField = nil
                    planner.pickTarget = field
                    planner.showSheet = false
                } label: {
                    Image(systemName: "mappin.and.ellipse").frame(width: 40, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(field == .from ? "Drop a pin for start" : "Drop a pin for destination")
                .accessibilityIdentifier(field == .from ? "fromPinButton" : "toPinButton")
                Menu {
                    ForEach([AccessMode.walk, .car, .scooter, .bike]) { option in
                        Button {
                            focusedField = nil
                            mode.wrappedValue = option
                        } label: {
                            if mode.wrappedValue == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Label(option.label, systemImage: option.icon)
                            }
                        }
                    }
                } label: {
                    Image(systemName: mode.wrappedValue.icon)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(field == .from ? "Get to the station by" : "Get from the station by")
                .accessibilityValue(mode.wrappedValue.label)
                .accessibilityIdentifier(field == .from ? "fromModeMenu" : "toModeMenu")
            }
        }
    }

    @ViewBuilder
    private func lookupFeedback(field: PlanField, text: String, point: PlanPoint?, planner: PlannerModel) -> some View {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           point?.name != text {
            Button {
                focusedField = nil
                Task { await planner.search(field) }
            } label: {
                Label(field == .from ? "Search start location" : "Search destination", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier(field == .from ? "searchFromLocationButton" : "searchToLocationButton")
        }
        if let error = planner.locationErrors[field] {
            Text(error).font(.caption).foregroundStyle(.red)
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
                Text("\(Int(itinerary.duration / 60)) min · \(distance(itinerary.distanceMeters))").font(.headline)
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
                            Text("\(leg.start, style: .time) – \(leg.end, style: .time) · \(Int(leg.duration / 60)) min · \(distance(leg.distanceMeters))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let note = status(leg) { Text(note.text).font(.caption2).foregroundStyle(note.color) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(selected ? Color.accentColor.opacity(0.12) : nil)
    }

    private func distance(_ meters: Double?) -> String {
        guard let meters else { return "distance unavailable" }
        return String(format: "%.1f mi est.", meters / 1_609.344)
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
