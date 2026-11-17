/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import XCTest
@testable import Atoll

/// NetEase Cloud Music clears its Now Playing info shortly after launch while
/// the song keeps playing. The lines fed in here are the ones the adapter
/// emitted around that, recorded on 2026-11-16 with the artwork left out.
@MainActor
final class NowPlayingClearTests: XCTestCase {

    private static let neteaseTrack = """
        {"diff":false,"payload":{"playing":true,"timestampEpochMicros":1794884017592140,\
        "album":"罗曼蒂克","elapsedTimeMicros":0,"playbackRate":1,\
        "bundleIdentifier":"com.netease.163music","processIdentifier":68304,"title":"罗曼蒂克",\
        "durationMicros":128127718,"artist":"Kevin罗凯文/Top Barry"}}
        """
    private static let neteaseNextTrack = """
        {"diff":false,"payload":{"playing":true,"timestampEpochMicros":1794883623182556,\
        "album":"荧光海","elapsedTimeMicros":0,"playbackRate":1,\
        "bundleIdentifier":"com.netease.163music","processIdentifier":68304,\
        "title":"荧光海（Feat.Top.Barry)","durationMicros":180843337,"artist":"Yaoanzhu/Top Barry"}}
        """
    private static let spotifyTrack = """
        {"diff":false,"payload":{"playing":true,"elapsedTimeMicros":0,"playbackRate":1,\
        "bundleIdentifier":"com.spotify.client","title":"Song","artist":"Artist","album":"Album",\
        "durationMicros":200000000}}
        """
    private static let clear = #"{"diff":false,"payload":{}}"#

    private var runningApplications: Set<String> = []

    /// A controller whose adapter is a stand-in that never writes a line, so
    /// the only updates it sees are the ones a test feeds it.
    private func makeController() throws -> NowPlayingController {
        let controller = try XCTUnwrap(NowPlayingController(
            adapterCommand: { .init(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]) },
            isApplicationRunning: { [unowned self] in self.runningApplications.contains($0) }
        ))
        addTeardownBlock { @MainActor in controller.stop() }
        return controller
    }

    private func feed(_ line: String, to controller: NowPlayingController) async throws {
        let update = try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(line.utf8))
        await controller.handleAdapterUpdate(update)
    }

    func testOnlyAFullUpdateNamingNoAppOrTrackReportsNothingPlaying() throws {
        func update(_ line: String) throws -> NowPlayingUpdate {
            try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(line.utf8))
        }

        XCTAssertTrue(try update(Self.clear).reportsNothingPlaying)
        XCTAssertFalse(try update(Self.neteaseTrack).reportsNothingPlaying)
        // A diff that carries no track is "nothing changed here", not a clear.
        XCTAssertFalse(try update(#"{"diff":true,"payload":{"playing":false}}"#).reportsNothingPlaying)
    }

    func testAClearFromRunningNetEaseKeepsTheSongPlaying() async throws {
        runningApplications = [MediaAppBundleID.neteaseMusic]
        let controller = try makeController()
        try await feed(Self.neteaseTrack, to: controller)

        try await feed(Self.clear, to: controller)

        XCTAssertEqual(controller.playbackState.title, "罗曼蒂克")
        XCTAssertEqual(controller.playbackState.bundleIdentifier, MediaAppBundleID.neteaseMusic)
        XCTAssertTrue(controller.playbackState.isPlaying)
    }

    func testTheNextTrackReplacesTheSongKeptThroughAClear() async throws {
        runningApplications = [MediaAppBundleID.neteaseMusic]
        let controller = try makeController()
        try await feed(Self.neteaseTrack, to: controller)
        try await feed(Self.clear, to: controller)

        try await feed(Self.neteaseNextTrack, to: controller)

        XCTAssertEqual(controller.playbackState.title, "荧光海（Feat.Top.Barry)")
        XCTAssertEqual(controller.playbackState.duration, 180.843337, accuracy: 0.000001)
        XCTAssertTrue(controller.playbackState.isPlaying)
    }

    func testTheClearIsAppliedOnceNetEaseQuits() async throws {
        runningApplications = [MediaAppBundleID.neteaseMusic]
        let controller = try makeController()
        try await feed(Self.neteaseTrack, to: controller)
        try await feed(Self.clear, to: controller)

        controller.applicationDidTerminate(bundleIdentifier: MediaAppBundleID.spotify)
        XCTAssertEqual(controller.playbackState.title, "罗曼蒂克", "another app quitting changes nothing")

        controller.applicationDidTerminate(bundleIdentifier: MediaAppBundleID.neteaseMusic)

        XCTAssertEqual(controller.playbackState.title, "")
        XCTAssertFalse(controller.playbackState.isPlaying)
    }

    func testQuittingNetEaseAfterItPublishedAgainClearsNothing() async throws {
        runningApplications = [MediaAppBundleID.neteaseMusic]
        let controller = try makeController()
        try await feed(Self.neteaseTrack, to: controller)
        try await feed(Self.clear, to: controller)
        try await feed(Self.neteaseNextTrack, to: controller)

        controller.applicationDidTerminate(bundleIdentifier: MediaAppBundleID.neteaseMusic)

        XCTAssertEqual(controller.playbackState.title, "荧光海（Feat.Top.Barry)",
                       "the clear that was held back was superseded; only a new one may empty the state")
    }

    func testAClearFromNetEaseThatHasQuitIsBelieved() async throws {
        runningApplications = [MediaAppBundleID.neteaseMusic]
        let controller = try makeController()
        try await feed(Self.neteaseTrack, to: controller)

        runningApplications = []
        try await feed(Self.clear, to: controller)

        XCTAssertEqual(controller.playbackState.title, "")
        XCTAssertFalse(controller.playbackState.isPlaying)
    }

    func testAClearFromAnotherRunningPlayerIsBelieved() async throws {
        runningApplications = [MediaAppBundleID.spotify]
        let controller = try makeController()
        try await feed(Self.spotifyTrack, to: controller)

        try await feed(Self.clear, to: controller)

        XCTAssertEqual(controller.playbackState.title, "")
        XCTAssertFalse(controller.playbackState.isPlaying)
    }
}
