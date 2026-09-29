/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import Combine
import Foundation

extension Notification.Name {
	static let sharingDidFinish = Notification.Name("com.ebullioscopic.sharingDidFinish")
}

@MainActor
final class SharingStateManager: ObservableObject {
	static let shared = SharingStateManager()

	private var activeSessions: Int = 0 {
		didSet {
			let newValue = activeSessions > 0
			if newValue != preventNotchClose {
				preventNotchClose = newValue
				if !newValue {
					NotificationCenter.default.post(name: .sharingDidFinish, object: nil)
				}
			}
		}
	}

	@Published var preventNotchClose: Bool = false

	private var activeDelegates: [UUID: SharingLifecycleDelegate] = [:]

	private init() {}
	
	func requestCloseIfReady() {
		if !preventNotchClose {
			NotificationCenter.default.post(name: .sharingDidFinish, object: nil)
		}
	}

	func beginInteraction() {
		activeSessions += 1
	}

	func endInteraction() {
		if activeSessions > 0 { activeSessions -= 1 }
	}

	func makeDelegate(onEnd: ((Bool) -> Void)? = nil) -> SharingLifecycleDelegate {
		let id = UUID()
		let delegate = SharingLifecycleDelegate(id: id, onEnd: { [weak self] succeeded in
			onEnd?(succeeded)
			self?.unregisterDelegate(id: id)
		}, onBegin: { [weak self] in
			self?.beginInteraction()
		}, onFinish: { [weak self] in
			self?.endInteraction()
		})
		activeDelegates[id] = delegate
		return delegate
	}

	private func unregisterDelegate(id: UUID) {
		activeDelegates.removeValue(forKey: id)
	}
}

final class SharingLifecycleDelegate: NSObject, NSSharingServiceDelegate, NSSharingServicePickerDelegate {
	let id: UUID
	private let onEnd: (Bool) -> Void
	private let onBegin: () -> Void
	private let onFinish: () -> Void

	private var pickerActive = false
	private var serviceInProgress = false
	private var finished = false
	private var retainedService: NSSharingService?
    private var retainedPicker: NSSharingServicePicker?

    func retainPicker(_ picker: NSSharingServicePicker) { retainedPicker = picker }
    func retainService(_ service: NSSharingService) { retainedService = service }

	init(id: UUID, onEnd: @escaping (Bool) -> Void, onBegin: @escaping () -> Void, onFinish: @escaping () -> Void) {
		self.id = id
		self.onEnd = onEnd
		self.onBegin = onBegin
		self.onFinish = onFinish
	}
	

	func markPickerBegan() {
		guard !pickerActive else { return }
		pickerActive = true
		onBegin()
	}

	func markServiceBegan() {
		guard !serviceInProgress else { return }
		serviceInProgress = true
		onBegin()
	}
	
	private func finishIfNeeded(succeeded: Bool = false) {
		guard !finished else { return }
		finished = true
        retainedService?.delegate = nil
        retainedService = nil
        retainedPicker?.delegate = nil
        retainedPicker = nil
		onFinish()
		onEnd(succeeded)
	}

	// MARK: - NSSharingServicePickerDelegate

    func sharingServicePicker(_ picker: NSSharingServicePicker, delegateFor service: NSSharingService) -> NSSharingServiceDelegate? {
        self
    }

	func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
		if service == nil {
			if pickerActive && !serviceInProgress {
				finishIfNeeded()
			}
			return
		}

        retainedService = service
        retainedPicker = nil
		service?.delegate = self
		serviceInProgress = true
	}

	// MARK: - NSSharingServiceDelegate

	func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
		if !pickerActive && !serviceInProgress {
			onBegin()
		}
		serviceInProgress = true
	}

	func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
		finishIfNeeded(succeeded: true)
	}

	func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        if (error as NSError).code != NSUserCancelledError {
            Task { @MainActor in
                ShelfStateViewModel.shared.report(String(localized: "Sharing failed. Your Shelf items have been kept."))
            }
        }
		finishIfNeeded()
	}
}

