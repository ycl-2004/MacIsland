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
import Combine
import XCTest
@testable import Atoll

@MainActor
final class MusicManagerPlaybackTests: XCTestCase {
    func testOptimisticPauseIgnoresStalePlayingEventUntilPausedIsConfirmed() {
        var transition = OptimisticPlaybackTransition()
        transition.begin(expecting: false)

        XCTAssertFalse(transition.shouldApply(eventIsPlaying: true))
        XCTAssertEqual(transition.expectedState, false)
        XCTAssertTrue(transition.shouldApply(eventIsPlaying: false))
        XCTAssertNil(transition.expectedState)
    }

    func testOptimisticResumeIgnoresStalePausedEventUntilPlayingIsConfirmed() {
        var transition = OptimisticPlaybackTransition()
        transition.begin(expecting: true)

        XCTAssertFalse(transition.shouldApply(eventIsPlaying: false))
        XCTAssertEqual(transition.expectedState, true)
        XCTAssertTrue(transition.shouldApply(eventIsPlaying: true))
        XCTAssertNil(transition.expectedState)
    }

    func testManualTrackArtworkHandoffDelaysPosterBy225Milliseconds() async {
        let manager = MusicManager(startsControllerSetup: false)
        let newArtwork = NSImage(size: NSSize(width: 48, height: 48))
        let artworkPublished = expectation(description: "delayed artwork published")
        let startedAt = Date()
        var observedDelay: TimeInterval = 0
        let cancellable = manager.$albumArt.sink { artwork in
            guard artwork === newArtwork else { return }
            observedDelay = Date().timeIntervalSince(startedAt)
            artworkPublished.fulfill()
        }
        defer { manager.destroy() }

        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: newArtwork)

        XCTAssertFalse(manager.albumArt === newArtwork)
        await fulfillment(of: [artworkPublished], timeout: 1)
        XCTAssertGreaterThanOrEqual(observedDelay, 0.20)
        withExtendedLifetime(cancellable) {}
    }

    func testRepeatedManualTrackHandoffPreservesPendingPosterWhenArtworkDoesNotChange() async {
        let manager = MusicManager(startsControllerSetup: false)
        let sharedArtwork = NSImage(size: NSSize(width: 48, height: 48))
        let artworkPublished = expectation(description: "pending shared artwork published")
        let cancellable = manager.$albumArt.sink { artwork in
            guard artwork === sharedArtwork else { return }
            artworkPublished.fulfill()
        }
        defer { manager.destroy() }

        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: sharedArtwork)
        manager.beginManualTrackArtworkHandoff()

        await fulfillment(of: [artworkPublished], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }

    func testRepeatedManualTrackHandoffPublishesOnlyNewestPoster() async {
        let manager = MusicManager(startsControllerSetup: false)
        let firstArtwork = NSImage(size: NSSize(width: 48, height: 48))
        let newestArtwork = NSImage(size: NSSize(width: 64, height: 64))
        let newestArtworkPublished = expectation(description: "newest artwork published")
        var firstArtworkWasPublished = false
        let cancellable = manager.$albumArt.sink { artwork in
            if artwork === firstArtwork {
                firstArtworkWasPublished = true
            } else if artwork === newestArtwork {
                newestArtworkPublished.fulfill()
            }
        }
        defer { manager.destroy() }

        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: firstArtwork)
        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: newestArtwork)

        await fulfillment(of: [newestArtworkPublished], timeout: 1)
        XCTAssertFalse(firstArtworkWasPublished)
        withExtendedLifetime(cancellable) {}
    }

    func testAutomaticTrackArtworkUpdateAppliesImmediatelyWithoutManualHandoff() {
        let manager = MusicManager(startsControllerSetup: false)
        let oldArtwork = NSImage(size: NSSize(width: 24, height: 24))
        let newArtwork = NSImage(size: NSSize(width: 32, height: 32))
        defer { manager.destroy() }

        manager.updateAlbumArt(newAlbumArt: oldArtwork)
        manager.updateAlbumArt(newAlbumArt: newArtwork)

        XCTAssertTrue(manager.albumArt === newArtwork)
    }
}
