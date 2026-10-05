/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import SwiftUI
import XCTest
@testable import Atoll

@MainActor
final class NotchWindowHostingTests: XCTestCase {
    func testAnimatedTrackAndLyricsUpdatesKeepTheWindowFrameStable() async throws {
        let state = TrackContentState()
        let hosting = FirstMouseHostingView(rootView: TrackContent(state: state))
        let window = makeWindow(hosting: hosting)
        defer { tearDownWindow(window) }
        let managedFrame = window.frame

        // Overlap updates with in-flight animations. The oversized content
        // also exercises the ScrollView / safe-area invalidation in the crash.
        for revision in 1...120 {
            state.revision = revision
            try await Task.sleep(for: .milliseconds(10))
            XCTAssertEqual(window.frame, managedFrame, "track update \(revision)")
        }
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(window.frame, managedFrame)
        XCTAssertEqual(hosting.frame.size, managedFrame.size)
        XCTAssertTrue(hosting.acceptsFirstMouse(for: nil))
    }

    func testHostingViewFollowsExplicitWindowResizes() async throws {
        let state = TrackContentState()
        let hosting = FirstMouseHostingView(rootView: TrackContent(state: state))
        let window = makeWindow(hosting: hosting)
        defer { tearDownWindow(window) }

        for size in [NSSize(width: 880, height: 400), NSSize(width: 480, height: 280)] {
            let target = NSRect(origin: window.frame.origin, size: size)
            window.setFrame(target, display: true)
            state.revision += 1
            try await Task.sleep(for: .milliseconds(200))

            XCTAssertEqual(window.frame, target)
            XCTAssertEqual(window.contentView?.bounds.size, size)
            XCTAssertEqual(hosting.frame.size, size)
        }
    }

    private func makeWindow<Content: View>(hosting: FirstMouseHostingView<Content>) -> NSPanel {
        let window = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 640, height: 222),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting.makeFrameManagedContainer(size: window.frame.size)
        window.alphaValue = 0
        window.orderFrontRegardless()
        return window
    }

    private func tearDownWindow(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
}

@MainActor
private final class TrackContentState: ObservableObject {
    @Published var revision = 0
}

private struct TrackContent: View {
    @ObservedObject var state: TrackContentState

    var body: some View {
        VStack {
            Text(state.revision.isMultiple(of: 2) ? "Short title" : String(repeating: "Track title ", count: 20))
            ScrollView {
                VStack {
                    ForEach(0..<(state.revision.isMultiple(of: 2) ? 2 : 80), id: \.self) { line in
                        Text("Lyric \(line) for track \(state.revision)")
                    }
                }
            }
        }
        .frame(
            width: state.revision.isMultiple(of: 2) ? 320 : 804,
            height: state.revision.isMultiple(of: 2) ? 80 : 1242
        )
        .animation(.smooth(duration: 0.15), value: state.revision)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
