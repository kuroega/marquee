import Foundation
import XCTest
@testable import AListTV

final class NowPlayingCenterTests: XCTestCase {
    func testFallbackUsesFileNameUnderFolderName() {
        let metadata = NowPlayingMetadata.fallback(name: "Episode 03.mkv", path: "/Shows/Some Show/Episode 03.mkv")
        XCTAssertEqual(metadata.title, "Episode 03")
        XCTAssertEqual(metadata.subtitle, "Some Show")
        XCTAssertTrue(metadata.artworkURLs.isEmpty)
    }

    func testFallbackAtRootHasNoSubtitle() {
        let metadata = NowPlayingMetadata.fallback(name: "clip.mp4", path: "/clip.mp4")
        XCTAssertEqual(metadata.title, "clip")
        XCTAssertNil(metadata.subtitle)
    }

    func testFirstTimingAlwaysPublishes() {
        let timing = NowPlayingTiming(elapsed: 5, duration: 100, isPlaying: true)
        XCTAssertTrue(timing.needsUpdate(from: nil, now: 0, publishedAt: 0))
    }

    func testSteadyPlaybackIsExtrapolated() {
        let published = NowPlayingTiming(elapsed: 10, duration: 100, isPlaying: true)
        let later = NowPlayingTiming(elapsed: 15.2, duration: 100, isPlaying: true)
        XCTAssertFalse(later.needsUpdate(from: published, now: 105, publishedAt: 100))
    }

    func testSeekOrStallPublishes() {
        let published = NowPlayingTiming(elapsed: 10, duration: 100, isPlaying: true)
        XCTAssertTrue(NowPlayingTiming(elapsed: 40, duration: 100, isPlaying: true).needsUpdate(from: published, now: 101, publishedAt: 100))
        XCTAssertTrue(NowPlayingTiming(elapsed: 10, duration: 100, isPlaying: true).needsUpdate(from: published, now: 105, publishedAt: 100))
    }

    func testRateOrDurationChangePublishes() {
        let published = NowPlayingTiming(elapsed: 10, duration: 0, isPlaying: true)
        XCTAssertTrue(NowPlayingTiming(elapsed: 10, duration: 0, isPlaying: false).needsUpdate(from: published, now: 100, publishedAt: 100))
        XCTAssertTrue(NowPlayingTiming(elapsed: 10, duration: 1_800, isPlaying: true).needsUpdate(from: published, now: 100, publishedAt: 100))
    }

    func testPausedTimeDoesNotAdvance() {
        let published = NowPlayingTiming(elapsed: 10, duration: 100, isPlaying: false)
        XCTAssertFalse(NowPlayingTiming(elapsed: 10, duration: 100, isPlaying: false).needsUpdate(from: published, now: 160, publishedAt: 100))
    }
}
