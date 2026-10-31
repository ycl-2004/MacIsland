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

/// The Micro Events tab: a list of the user's own recurring items, and an
/// in-place editor. Both fit the fixed open-notch height, so the editor replaces
/// the list instead of pushing anything taller.
struct NotchMicroEventsView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var store: MicroEventStore
    @ObservedObject private var manager = MicroEventManager.shared
    @Default(.enableMicroEventsFeature) private var isEnabled

    @State private var draft: MicroEvent?
    @State private var draftIsNew = false
    @State private var timeText = "09:00"
    @State private var timeIsValid = true
    @State private var now = Date()
    @State private var pendingDeletion: MicroEvent?
    @State private var showingRecurrenceOptions = false
    @State private var autoCloseToken = UUID()
    @State private var editingToken = UUID()
    @StateObject private var windowReference = MicroEventWindowReference()
    @FocusState private var focusedField: EditorField?

    private enum EditorField: Hashable { case title, time }

    @MainActor
    init(store: MicroEventStore? = nil, draft: MicroEvent? = nil) {
        _store = ObservedObject(wrappedValue: store ?? .shared)
        _draft = State(initialValue: draft)
        _draftIsNew = State(initialValue: draft != nil)
        _timeText = State(initialValue: draft.map { Self.timeText(hour: $0.hour, minute: $0.minute) } ?? "09:00")
    }

    private var headerHeight: CGFloat { max(24, vm.effectiveClosedNotchHeight) }

    private var contentHeight: CGFloat {
        let available = openNotchSize.height - headerHeight - 36
        return max(130, available)
    }

    var body: some View {
        Group {
            if let draft {
                editor(draft)
            } else {
                listContent
                    .padding(.trailing, 28)
                    .overlay(alignment: .topTrailing) { addButton }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: contentHeight, alignment: .top)
        .background(MicroEventWindowReader(reference: windowReference).frame(width: 0, height: 0))
        .task {
            store.loadIfNeeded()
            now = Date()
        }
        .onAppear {
            now = Date()
            updateAutoCloseSuppression()
        }
        .onDisappear {
            vm.setAutoCloseSuppression(false, token: autoCloseToken)
            store.endEditing(token: editingToken, performCleanup: isEnabled)
        }
        .onChange(of: draft != nil) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: pendingDeletion?.id) { _, _ in updateAutoCloseSuppression() }
        .onChange(of: store.events) { _, _ in now = Date() }
        .onChange(of: manager.refreshToken) { _, _ in now = Date() }
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
    }

    private var addButton: some View {
        Button {
            beginAdding()
        } label: {
            Image(systemName: "plus")
                .font(.notch(.caption, weight: .semibold))
                .frame(width: 22, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.inkSecondary)
        .help(String(localized: "Add a Micro Event"))
        .accessibilityLabel(String(localized: "Add a Micro Event"))
        .disabled(!isEnabled)
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        if !isEnabled {
            disabledState
        } else if let error = store.errorMessage {
            Text(error)
                .font(.notch(.caption))
                .foregroundStyle(.statusAttention)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !store.isLoaded, store.events.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sortedEvents.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(sortedEvents) { event in
                        MicroEventRow(
                            event: event,
                            now: now,
                            occurrence: event.currentOrNextOccurrence(from: now),
                            onToggle: { toggle(event) },
                            onEdit: { beginEditing(event) },
                            onToggleEnabled: {
                                store.setEnabled(!event.isEnabled, for: event.id)
                                store.saveNow()
                            },
                            onDelete: { pendingDeletion = event }
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var sortedEvents: [MicroEvent] {
        store.events.sorted { lhs, rhs in
            let lhsDate = lhs.currentOrNextOccurrence(from: now)
            let rhsDate = rhs.currentOrNextOccurrence(from: now)
            let lhsDone = lhsDate.map { lhs.isCompleted($0) } ?? false
            let rhsDone = rhsDate.map { rhs.isCompleted($0) } ?? false
            if lhsDone != rhsDone { return !lhsDone }
            switch (lhsDate, rhsDate) {
            case let (lhs?, rhs?): return lhs < rhs
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("Nothing scheduled yet")
                .font(.notch(.body))
                .foregroundStyle(.inkSecondary)
            Text("Add something you want to be reminded of every day, week or month.")
                .font(.notch(.caption))
                .foregroundStyle(.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disabledState: some View {
        VStack(spacing: 6) {
            Text("Micro Events is off")
                .font(.notch(.body))
                .foregroundStyle(.inkSecondary)
            Button("Turn it on in Settings") {
                SettingsWindowController.shared.showWindow(tab: "microEvents")
            }
            .buttonStyle(.plain)
            .font(.notch(.caption))
            .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editor

    private func editor(_ draft: MicroEvent) -> some View {
        let binding = Binding<MicroEvent>(
            get: { self.draft ?? draft },
            set: { self.draft = $0 }
        )
        return VStack(alignment: .leading, spacing: 6) {
            TextField(String(localized: "What do you want to remember?"), text: binding.title)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .title)
                .simultaneousGesture(TapGesture().onEnded { focus(.title) })
                .font(.notch(.body))
                .foregroundStyle(.inkPrimary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: NotchRadius.control).fill(.fillControl))

            HStack(spacing: 8) {
                Button {
                    showingRecurrenceOptions = true
                } label: {
                    HStack(spacing: 4) {
                        Text(binding.wrappedValue.recurrence.localizedName)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .font(.notch(.caption, weight: .medium))
                    .foregroundStyle(.inkPrimary)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: NotchRadius.control).fill(.fillControl))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Repeat"))
                .fixedSize()
                .popover(isPresented: $showingRecurrenceOptions, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(MicroEventRecurrence.allCases) { recurrence in
                            Button {
                                binding.wrappedValue.recurrence = recurrence
                                showingRecurrenceOptions = false
                            } label: {
                                HStack {
                                    Text(recurrence.localizedName)
                                    Spacer()
                                    if binding.wrappedValue.recurrence == recurrence {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .frame(width: 140)
                }
                timeField
                scheduleControls(binding)
                Spacer(minLength: 0)
            }
            .frame(height: 24)

            HStack(spacing: 8) {
                if let message = validationMessage(for: draft) {
                    Text(message)
                        .font(.notch(.caption))
                        .foregroundStyle(.statusAttention)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("Cancel") { cancelEditing() }
                    .buttonStyle(.plain)
                    .font(.notch(.caption))
                    .foregroundStyle(.inkSecondary)
                Button(draftIsNew ? "Add" : "Save") { commit(draft) }
                    .buttonStyle(.plain)
                    .font(.notch(.caption, weight: .semibold))
                    .foregroundStyle(canCommit(draft) ? Color.accentColor : .inkQuaternary)
                    .disabled(!canCommit(draft))
            }
            .frame(height: 22)
        }
        .onExitCommand { cancelEditing() }
        .suppressesNotchSwipeGestures()
    }

    private var timeField: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.notch(.caption))
                .foregroundStyle(.inkTertiary)
            TextField("09:00", text: $timeText)
                .textFieldStyle(.plain)
                .font(.notch(.body, design: .monospaced))
                .frame(width: 64)
                .focused($focusedField, equals: .time)
                .accessibilityLabel(String(localized: "Reminder time"))
                .simultaneousGesture(TapGesture().onEnded { focus(.time) })
                .onChange(of: timeText) { _, _ in
                    timeIsValid = MicroEventTimeParser.time(from: timeText) != nil
                    applyTimeToDraft()
                }
                .onSubmit {
                    applyTimeToDraft()
                    if let time = MicroEventTimeParser.time(from: timeText) {
                        timeText = Self.timeText(hour: time.hour, minute: time.minute)
                    }
                }
        }
        .foregroundStyle(timeIsValid ? .inkPrimary : .statusDanger)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: NotchRadius.control).fill(.fillControl))
        .help(String(localized: "Type a time like 9, 930, 09:30 or 6:30 PM"))
    }

    @ViewBuilder
    private func scheduleControls(_ binding: Binding<MicroEvent>) -> some View {
        switch binding.wrappedValue.recurrence {
        case .once:
            DatePicker(String(localized: "Date"), selection: binding.startDate, displayedComponents: .date)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel(String(localized: "Reminder date"))
            .fixedSize()
        case .daily:
            EmptyView()
        case .weekly:
            HStack(spacing: 3) {
                ForEach(MicroEvent.orderedWeekdays, id: \.self) { weekday in
                    let isOn = binding.wrappedValue.weekdays.contains(weekday)
                    Button {
                        if isOn {
                            binding.wrappedValue.weekdays.remove(weekday)
                        } else {
                            binding.wrappedValue.weekdays.insert(weekday)
                        }
                    } label: {
                        Text(MicroEvent.weekdaySymbol(for: weekday))
                            .font(.notch(.caption, weight: .medium))
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isOn ? AnyShapeStyle(.fillControlHover) : AnyShapeStyle(.clear))
                            )
                            .foregroundStyle(isOn ? .inkPrimary : .inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.autoupdatingCurrent.standaloneWeekdaySymbols[weekday - 1])
                    .accessibilityValue(isOn ? String(localized: "Selected") : String(localized: "Not selected"))
                }
            }
        case .monthly:
            HStack(spacing: 6) {
                Text(String(localized: "Day"))
                    .font(.notch(.caption))
                    .foregroundStyle(.inkTertiary)
                Stepper(value: binding.dayOfMonth, in: 1...31) {
                    Text("\(binding.wrappedValue.dayOfMonth)")
                        .font(.notch(.body, design: .monospaced))
                        .foregroundStyle(.inkPrimary)
                }
                .fixedSize()
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: NotchRadius.control).fill(.fillControl))
        }
    }

    // MARK: - Editing

    private func beginAdding() {
        vm.setAutoCloseSuppression(true, token: autoCloseToken)
        var event = MicroEvent(title: "", recurrence: .daily)
        event.hour = 9
        event.minute = 0
        event.weekdays = [Calendar.autoupdatingCurrent.component(.weekday, from: Date())]
        event.startDate = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        draft = event
        draftIsNew = true
        timeText = Self.timeText(hour: event.hour, minute: event.minute)
        timeIsValid = true
    }

    private func beginEditing(_ event: MicroEvent) {
        vm.setAutoCloseSuppression(true, token: autoCloseToken)
        store.beginEditing(id: event.id, token: editingToken)
        var event = event
        if event.recurrence == .once {
            event.hour = Calendar.autoupdatingCurrent.component(.hour, from: event.startDate)
            event.minute = Calendar.autoupdatingCurrent.component(.minute, from: event.startDate)
        }
        draft = event
        draftIsNew = false
        timeText = Self.timeText(hour: event.hour, minute: event.minute)
        timeIsValid = true
    }

    private func cancelEditing() {
        showingRecurrenceOptions = false
        focusedField = nil
        draft = nil
        draftIsNew = false
        store.endEditing(token: editingToken, performCleanup: isEnabled)
    }

    private func applyTimeToDraft() {
        guard var event = draft,
              let time = MicroEventTimeParser.time(from: timeText) else { return }
        event.hour = time.hour
        event.minute = time.minute
        draft = event
    }

    private func commit(_ event: MicroEvent) {
        applyTimeToDraft()
        guard let current = draft else { return }
        var normalized = current.normalized()
        if normalized.recurrence == .once {
            guard let date = normalized.onceDate(), date > Date() else { return }
            if !draftIsNew, let original = store.events.first(where: { $0.id == normalized.id }),
               original.recurrence != .once || original.startDate != date {
                normalized.completedKeys.removeAll { $0 == MicroEvent.onceKey }
                normalized.completedAt = nil
            }
            normalized.startDate = date
        }
        if draftIsNew {
            store.add(normalized)
        } else {
            store.update(normalized)
        }
        store.saveNow()
        showingRecurrenceOptions = false
        focusedField = nil
        draft = nil
        draftIsNew = false
        store.endEditing(token: editingToken, performCleanup: isEnabled)
    }

    private func canCommit(_ event: MicroEvent) -> Bool {
        validationMessage(for: event) == nil && timeIsValid
    }

    private func validationMessage(for event: MicroEvent) -> String? {
        if let message = event.errorMessage { return message }
        if event.recurrence == .once, (event.onceDate() ?? .distantPast) <= Date() {
            return String(localized: "Choose a future date and time.")
        }
        return nil
    }

    private func toggle(_ event: MicroEvent) {
        guard let occurrence = event.currentOrNextOccurrence(from: now) else { return }
        store.setCompleted(!event.isCompleted(occurrence), occurrence: occurrence, for: event.id)
        store.saveNow()
    }

    // MARK: - Helpers

    private static func timeText(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private func updateAutoCloseSuppression() {
        let active = draft != nil || pendingDeletion != nil
        let wasSuppressed = vm.isAutoCloseSuppressed
        vm.setAutoCloseSuppression(active, token: autoCloseToken)
        if wasSuppressed && !vm.isAutoCloseSuppressed { vm.shouldRecheckHover.toggle() }
    }

    private func focus(_ field: EditorField) {
        NSApp.activate()
        windowReference.window?.makeKey()
        DispatchQueue.main.async { focusedField = field }
    }

}

private final class MicroEventWindowReference: ObservableObject {
    weak var window: NSWindow?
}

private struct MicroEventWindowReader: NSViewRepresentable {
    let reference: MicroEventWindowReference

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.reference = reference
        return view
    }

    func updateNSView(_ view: WindowReaderView, context: Context) {
        view.reference = reference
        reference.window = view.window
    }

    final class WindowReaderView: NSView {
        weak var reference: MicroEventWindowReference?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reference?.window = window
        }
    }
}

private extension MicroEvent {
    var errorMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Give it a name.")
        }
        if recurrence == .weekly && weekdays.isEmpty {
            return String(localized: "Pick at least one day.")
        }
        return nil
    }
}

/// A compact row with the event and its schedule on one line.
struct MicroEventRow: View {
    let event: MicroEvent
    let now: Date
    let occurrence: Date?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onToggleEnabled: () -> Void
    let onDelete: () -> Void

    private var isDone: Bool {
        guard let occurrence else { return false }
        return event.isCompleted(occurrence)
    }

    var isOverdue: Bool {
        guard let occurrence, event.isEnabled, !isDone else { return false }
        return occurrence < now
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isDone ? AnyShapeStyle(.statusSuccess) : (isOverdue ? AnyShapeStyle(.statusDanger) : AnyShapeStyle(.inkTertiary)))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(occurrence == nil)
            .accessibilityLabel(isDone ? String(localized: "Mark not done") : String(localized: "Mark done"))
            .accessibilityValue(event.title)
            .help(isDone ? String(localized: "Mark this occurrence not done") : String(localized: "Mark this occurrence done"))

            HStack(spacing: 8) {
                Text(event.title)
                    .font(.notch(.body, weight: .medium))
                    .foregroundStyle(isOverdue ? AnyShapeStyle(.statusDanger) : (event.isEnabled ? (isDone ? AnyShapeStyle(.inkTertiary) : AnyShapeStyle(.inkPrimary)) : AnyShapeStyle(.inkTertiary)))
                    .strikethrough(isDone || !event.isEnabled, color: .inkTertiary)
                    .lineLimit(1)
                Text(scheduleLabel)
                    .font(.notch(.caption))
                    .foregroundStyle(isOverdue ? AnyShapeStyle(.statusDanger) : AnyShapeStyle(.inkTertiary))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let occurrence, !isDone && event.isEnabled {
                    Text(isOverdue ? String(localized: "Overdue") : MicroEvent.relativeDescription(for: occurrence, now: now))
                        .font(.notch(.caption, weight: isOverdue ? .semibold : .regular))
                        .foregroundStyle(isOverdue ? AnyShapeStyle(.statusDanger) : AnyShapeStyle(.inkTertiary))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onEdit)

            Button(action: onEdit) {
                Image(systemName: "pencil").frame(width: 20, height: 20)
            }
            .help(String(localized: "Edit"))
            .accessibilityLabel(String(format: String(localized: "Edit %@"), event.title))

            Button(action: onDelete) {
                Image(systemName: "trash").frame(width: 20, height: 20)
            }
            .help(String(localized: "Delete"))
            .accessibilityLabel(String(format: String(localized: "Delete %@"), event.title))
        }
        .frame(height: 28)
        .buttonStyle(.plain)
        .font(.notch(.caption, weight: .semibold))
        .foregroundStyle(.inkSecondary)
        .contentShape(Rectangle())
        .contextMenu {
            Button(String(localized: "Edit…"), action: onEdit)
            Button(event.isEnabled ? String(localized: "Pause") : String(localized: "Resume"), action: onToggleEnabled)
            Divider()
            Button(String(localized: "Delete"), role: .destructive, action: onDelete)
        }
    }

    private var scheduleLabel: String {
        if !event.isEnabled {
            return String(localized: "Paused")
        }
        if let occurrence, Calendar.autoupdatingCurrent.isDate(occurrence, inSameDayAs: now) {
            return "\(String(localized: "Today")) · \(event.scheduleDescription)"
        }
        return event.scheduleDescription
    }
}

/// Accepts a short hour, compact digits, or a colon-separated time, with an
/// optional AM/PM suffix. Invalid input is never silently clamped.
enum MicroEventTimeParser {
    struct Time: Equatable {
        let hour: Int
        let minute: Int
    }

    static func time(from text: String) -> Time? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        var isPM = false
        var isAM = false
        var digits = trimmed
        for suffix in ["p.m.", "pm", "p"] where digits.hasSuffix(suffix) {
            isPM = true
            digits = String(digits.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        for suffix in ["a.m.", "am", "a"] where digits.hasSuffix(suffix) {
            isAM = true
            digits = String(digits.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        let parts = digits.split(separator: ":", omittingEmptySubsequences: false)
        let hourText: String
        let minuteText: String
        if parts.count == 2 {
            guard (1...2).contains(parts[0].count), (1...2).contains(parts[1].count) else { return nil }
            hourText = String(parts[0])
            minuteText = String(parts[1])
        } else if parts.count == 1, (1...4).contains(digits.count), digits.allSatisfy(\.isNumber) {
            if digits.count <= 2 {
                hourText = digits
                minuteText = "0"
            } else {
                hourText = String(digits.dropLast(2))
                minuteText = String(digits.suffix(2))
            }
        } else {
            return nil
        }
        guard hourText.allSatisfy(\.isNumber), minuteText.allSatisfy(\.isNumber),
              let rawHour = Int(hourText), let minute = Int(minuteText),
              (0...59).contains(minute),
              (!(isAM || isPM) || (1...12).contains(rawHour)) else { return nil }

        var hour = rawHour
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        guard (0...23).contains(hour) else { return nil }
        return Time(hour: hour, minute: minute)
    }
}
