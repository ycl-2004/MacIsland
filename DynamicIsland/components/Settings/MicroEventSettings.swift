/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Defaults
import SwiftUI

struct MicroEventSettings: View {
    @ObservedObject private var store: MicroEventStore
    @ObservedObject private var manager = MicroEventManager.shared
    @Default(.enableMicroEventsFeature) private var isEnabled
    @Default(.microEventsLeadMinutes) private var leadMinutes
    @State private var now = Date()
    @State private var editor: MicroEventEditing?
    @State private var pendingDeletion: MicroEvent?
    @State private var editingToken = UUID()

    @MainActor
    init(store: MicroEventStore? = nil) {
        _store = ObservedObject(wrappedValue: store ?? .shared)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableMicroEventsFeature) {
                    Text("Enable Micro Events")
                }
                .settingsHighlight(id: "microEvents-Enable Micro Events")

                Defaults.Toggle(key: .microEventsPlaySound) {
                    Text("Reminder sound")
                }
                .settingsHighlight(id: "microEvents-Reminder sound")
                .disabled(!isEnabled)

                Picker("Remind me", selection: $leadMinutes) {
                    Text("At the time").tag(0)
                    Text("5 minutes before").tag(5)
                    Text("10 minutes before").tag(10)
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                }
                .pickerStyle(.menu)
                .disabled(!isEnabled)
            } header: {
                SettingsInfoLabel("Micro Events", info: "Adds a tab for your own daily, weekly or monthly items. Reminders use the notch and a chime, not system notifications, so Focus does not filter them.")
            }

            Section {
                if store.events.isEmpty {
                    Text("No Micro Events yet. Add one to get started.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.events.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) { event in
                        let occurrence = event.currentOrNextOccurrence(from: now)
                        let overdue = occurrence.map { event.isEnabled && !event.isCompleted($0) && $0 < now } ?? false
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title).foregroundStyle(overdue ? Color.red : Color.primary).lineLimit(1)
                                Text(event.isEnabled ? event.scheduleDescription : String(localized: "Paused"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if overdue { Text("Overdue").font(.caption).foregroundStyle(.red) }
                            Button("Edit") {
                                store.beginEditing(id: event.id, token: editingToken)
                                editor = MicroEventEditing(event: event, isNew: false)
                            }
                                .accessibilityLabel(String(format: String(localized: "Edit %@"), event.title))
                            Button("Delete", role: .destructive) { pendingDeletion = event }
                                .accessibilityLabel(String(format: String(localized: "Delete %@"), event.title))
                        }
                        .padding(.vertical, 3)
                    }
                }
                Button("Add Micro Event") {
                    let calendar = Calendar.autoupdatingCurrent
                    editor = MicroEventEditing(event: MicroEvent(
                        title: "", recurrence: .daily, hour: 9,
                        weekdays: [calendar.component(.weekday, from: Date())],
                        startDate: calendar.startOfDay(for: Date())), isNew: true)
                }
            } header: {
                Text("Your Micro Events")
            } footer: {
                Text("A tick belongs to one occurrence: a daily item starts unchecked tomorrow. Reminders only fire while Atoll is running.")
            }

            if let error = store.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Micro Events")
        .sheet(item: $editor) { editing in
            MicroEventSettingsEditor(editing: editing) { event in
                if editing.isNew { store.add(event) } else { store.update(event) }
                store.saveNow()
                editor = nil
                store.endEditing(token: editingToken, performCleanup: isEnabled)
            } onCancel: {
                editor = nil
                store.endEditing(token: editingToken, performCleanup: isEnabled)
            }
        }
        .confirmationDialog("Delete this Micro Event?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { event in
            Button("Delete", role: .destructive) {
                store.remove(id: event.id)
                store.saveNow()
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { event in
            Text("Delete \(event.title)? This cannot be undone.")
        }
        .task {
            store.loadIfNeeded()
            now = Date()
        }
        .onAppear { now = Date() }
        .onDisappear { store.endEditing(token: editingToken, performCleanup: isEnabled) }
        .onChange(of: editor?.id) { _, current in
            if current == nil { store.endEditing(token: editingToken, performCleanup: isEnabled) }
        }
        .onChange(of: manager.refreshToken) { _, _ in now = Date() }
    }
}

struct MicroEventEditing: Identifiable {
    let id = UUID()
    let event: MicroEvent
    let isNew: Bool
}

struct MicroEventSettingsEditor: View {
    let editing: MicroEventEditing
    let onSave: (MicroEvent) -> Void
    let onCancel: () -> Void
    @State private var event: MicroEvent
    @State private var time: Date

    init(editing: MicroEventEditing, onSave: @escaping (MicroEvent) -> Void, onCancel: @escaping () -> Void) {
        self.editing = editing
        self.onSave = onSave
        self.onCancel = onCancel
        let value = editing.event.preparedForEditing()
        _event = State(initialValue: value)
        _time = State(initialValue: Calendar.autoupdatingCurrent.date(bySettingHour: value.hour, minute: value.minute, second: 0, of: Date()) ?? Date())
    }

    private var prepared: MicroEvent? {
        var value = event
        let calendar = Calendar.autoupdatingCurrent
        value.hour = calendar.component(.hour, from: time)
        value.minute = calendar.component(.minute, from: time)
        return value.preparedForSaving(replacing: editing.isNew ? nil : editing.event)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing.isNew ? "Add Micro Event" : "Edit Micro Event").font(.headline)
            Form {
                TextField("Title", text: $event.title)
                Picker("Repeat", selection: $event.recurrence) {
                    ForEach(MicroEventRecurrence.allCases) { item in
                        Text(item.localizedName).tag(item)
                    }
                }
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                if event.recurrence == .once {
                    DatePicker("Date", selection: $event.startDate, displayedComponents: .date)
                } else if event.recurrence == .weekly {
                    HStack {
                        Text("Days")
                        Spacer()
                        ForEach(MicroEvent.orderedWeekdays, id: \.self) { weekday in
                            Toggle(MicroEvent.weekdaySymbol(for: weekday), isOn: Binding(
                                get: { event.weekdays.contains(weekday) },
                                set: { selected in
                                    if selected { event.weekdays.insert(weekday) }
                                    else { event.weekdays.remove(weekday) }
                                }
                            ))
                            .toggleStyle(.button)
                            .accessibilityLabel(Calendar.autoupdatingCurrent.standaloneWeekdaySymbols[weekday - 1])
                        }
                    }
                } else if event.recurrence == .monthly {
                    Stepper("Day \(event.dayOfMonth)", value: $event.dayOfMonth, in: 1...31)
                }
                if event.recurrence == .weekly && event.weekdays.isEmpty {
                    Text("Pick at least one day.").foregroundStyle(.secondary)
                } else if event.recurrence == .once && prepared == nil && event.isValid {
                    Text("Choose a future date and time.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(height: 250)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(editing.isNew ? "Add" : "Save") {
                    if let prepared { onSave(prepared) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(prepared == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
