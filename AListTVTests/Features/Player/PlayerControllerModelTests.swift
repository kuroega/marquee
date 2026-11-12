import Foundation
import XCTest
@testable import AListTV

final class PlayerControllerModelTests: XCTestCase {
    func testSeekTargetClampsAtZeroAndDuration() {
        XCTAssertEqual(PlaybackPresentation.clampedSeekTarget(-10, duration: 120), 0)
        XCTAssertEqual(PlaybackPresentation.clampedSeekTarget(130, duration: 120), 120)
        XCTAssertEqual(PlaybackPresentation.clampedSeekTarget(42, duration: 120), 42)
        XCTAssertEqual(PlaybackPresentation.clampedSeekTarget(-10, duration: 0), 0)
    }

    func testDirectSourcesUseTrustedCueDemuxer() {
        let mkv = URL(string: "http://10.0.0.2:5244/p/Shows/Episode%201.MKV?sign=abc")!
        XCTAssertEqual(PlaybackPresentation.vlcDemuxOption(for: mkv), ":demux=mkv_trusted,any")
        XCTAssertEqual(PlaybackPresentation.vlcDemuxOption(for: URL(string: "http://h/p/a.webm")!), ":demux=mkv_trusted,any")
        // Matroska saved as .mp4 must seek by its Cues too.
        XCTAssertEqual(PlaybackPresentation.vlcDemuxOption(for: URL(string: "http://h/p/a.mp4?sign=x")!), ":demux=mkv_trusted,any")
        XCTAssertNil(PlaybackPresentation.vlcDemuxOption(for: URL(string: "http://h/api/playback/id/index.m3u8")!))
    }

    func testProgressFractionClampsToTimelineBounds() {
        XCTAssertEqual(PlaybackPresentation.clampedProgressFraction(-10, duration: 120), 0)
        XCTAssertEqual(PlaybackPresentation.clampedProgressFraction(60, duration: 120), 0.5)
        XCTAssertEqual(PlaybackPresentation.clampedProgressFraction(130, duration: 120), 1)
        XCTAssertEqual(PlaybackPresentation.clampedProgressFraction(60, duration: 0), 0)
    }

    func testNearEndRequiresKnownDurationAndAllowsSmallTimingDrift() {
        XCTAssertFalse(PlaybackPresentation.isNearEnd(currentTime: 117.9, duration: 120))
        XCTAssertTrue(PlaybackPresentation.isNearEnd(currentTime: 118, duration: 120))
        XCTAssertTrue(PlaybackPresentation.isNearEnd(currentTime: 9.5, duration: 10))
        XCTAssertFalse(PlaybackPresentation.isNearEnd(currentTime: 1, duration: 0))
    }

    func testPlaybackSettingsStoreDefaultsToEnabledAndPersistsChanges() {
        let suite = "PlayerControllerModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackSettingsStore(defaults: defaults)

        XCTAssertTrue(store.loadAutoPlayNext())
        store.saveAutoPlayNext(false)
        XCTAssertFalse(store.loadAutoPlayNext())
    }

    func testScrubTargetUsesHorizontalTranslationAndClamps() {
        XCTAssertEqual(
            PlaybackPresentation.scrubTarget(currentTime: 45, horizontalTranslation: 30, duration: 120),
            55
        )
        XCTAssertEqual(
            PlaybackPresentation.scrubTarget(currentTime: 45, horizontalTranslation: -150, duration: 120),
            0
        )
        XCTAssertEqual(
            PlaybackPresentation.scrubTarget(currentTime: 115, horizontalTranslation: 60, duration: 120),
            120
        )
    }

    func testScrubTargetCanAccumulateAcrossSwipes() {
        let firstTarget = PlaybackPresentation.scrubTarget(currentTime: 45, horizontalTranslation: 30, duration: 120)
        let secondTarget = PlaybackPresentation.scrubTarget(currentTime: firstTarget, horizontalTranslation: 30, duration: 120)
        let reversedTarget = PlaybackPresentation.scrubTarget(currentTime: secondTarget, horizontalTranslation: -30, duration: 120)

        XCTAssertEqual(firstTarget, 55)
        XCTAssertEqual(secondTarget, 65)
        XCTAssertEqual(reversedTarget, 55)
    }

    func testRepeatedScrubTargetClampsAtTimelineBoundaries() {
        let endTarget = PlaybackPresentation.scrubTarget(currentTime: 115, horizontalTranslation: 60, duration: 120)
        let startTarget = PlaybackPresentation.scrubTarget(currentTime: 5, horizontalTranslation: -30, duration: 120)

        XCTAssertEqual(PlaybackPresentation.scrubTarget(currentTime: endTarget, horizontalTranslation: 60, duration: 120), 120)
        XCTAssertEqual(PlaybackPresentation.scrubTarget(currentTime: startTarget, horizontalTranslation: -30, duration: 120), 0)
    }

    func testResumeTimeTextIncludesHours() {
        XCTAssertEqual(PlaybackPresentation.resumeTimeText(0), "00:00:00")
        XCTAssertEqual(PlaybackPresentation.resumeTimeText(3_723), "01:02:03")
    }

    func testTrackLabelFallsBackAndExcludesURLLikeMetadata() {
        XCTAssertEqual(
            PlaybackPresentation.trackTitle(name: nil, description: nil, language: nil, fallback: "Audio 1"),
            "Audio 1"
        )
        XCTAssertEqual(
            PlaybackPresentation.trackTitle(name: " https://media.example/sub.srt?token=secret ", description: "Commentary", language: "en", fallback: "Subtitle 1"),
            "Commentary"
        )
        XCTAssertEqual(
            PlaybackPresentation.trackTitle(name: "English", description: "Commentary", language: "en", fallback: "Audio 1"),
            "English"
        )
    }

    func testFrameRateGuardsZeroDenominator() {
        XCTAssertNil(PlaybackPresentation.frameRate(numerator: 24, denominator: 0))
        XCTAssertEqual(PlaybackPresentation.frameRate(numerator: 24_000, denominator: 1_001)!, 23.976023976023978, accuracy: 0.000_001)
    }

    func testDiagnosticsFormattingHandlesAbsentMetadata() {
        XCTAssertEqual(PlaybackPresentation.diagnosticMetadata(nil, nil, nil), "—")
        XCTAssertEqual(PlaybackPresentation.diagnosticMetadata("English", "en", "AAC"), "English · en · AAC")
        XCTAssertEqual(PlaybackPresentation.diagnosticBitrate(125_000), "1.00 Mbit/s")
    }

    func testSeekTargetClampsUnknownDurationNegative() {
        XCTAssertEqual(PlaybackPresentation.clampedSeekTarget(-5, duration: 0), 0)
        XCTAssertEqual(PlaybackPresentation.clampedSeekTarget(999, duration: 0), 999)
    }

    func testTrackTitleFiltersQueryStrings() {
        XCTAssertEqual(
            PlaybackPresentation.trackTitle(name: nil, description: "cdn.example.com?token=abc", language: "en", fallback: "Sub 1"),
            "en"
        )
    }

    func testDiagnosticBitrateConversion() {
        XCTAssertEqual(PlaybackPresentation.diagnosticBitrate(0), "0.00 Mbit/s")
    }

    func testDiagnosticMetadataPartialValues() {
        XCTAssertEqual(PlaybackPresentation.diagnosticMetadata("English", nil, "AAC"), "English · AAC")
        XCTAssertEqual(PlaybackPresentation.diagnosticMetadata(nil, "en", nil), "en")
    }

    func testDiagnosticsHistoryDerivesRatesFromCounters() {
        var history = PlaybackDiagnosticsHistory()
        history.record(diagnosticsSnapshot(input: 125_000, shown: 100, late: 0), at: 10)
        history.record(diagnosticsSnapshot(input: 250_000, shown: 124, late: 2), at: 11)

        XCTAssertEqual(history.samples.count, 2)
        XCTAssertNil(history.samples[0].renderedFPS, "The first sample has nothing to diff against")
        XCTAssertEqual(history.samples[1].elapsed, 1)
        XCTAssertEqual(history.samples[1].inputMbps, 2, accuracy: 0.000_1)
        XCTAssertEqual(history.samples[1].renderedFPS ?? -1, 24, accuracy: 0.000_1)
        XCTAssertEqual(history.samples[1].droppedFPS, 2, accuracy: 0.000_1)
    }

    func testDiagnosticsHistoryThrottlesAndTrimsToWindow() {
        var history = PlaybackDiagnosticsHistory()
        history.record(diagnosticsSnapshot(input: 0, shown: 0, late: 0), at: 0)
        history.record(diagnosticsSnapshot(input: 0, shown: 0, late: 0), at: 0.2)
        XCTAssertEqual(history.samples.count, 1, "Snapshots closer than a second apart are skipped")

        for second in 1...90 { history.record(diagnosticsSnapshot(input: 0, shown: 0, late: 0), at: Double(second)) }
        XCTAssertEqual(history.samples.first?.elapsed, 30)
        XCTAssertEqual(history.samples.last?.elapsed, 90)
    }

    func testDiagnosticsHistoryIgnoresCounterResets() {
        var history = PlaybackDiagnosticsHistory()
        history.record(diagnosticsSnapshot(input: 0, shown: 500, late: 9), at: 0)
        history.record(diagnosticsSnapshot(input: 0, shown: 10, late: 0), at: 1)
        XCTAssertNil(history.samples[1].renderedFPS)
        XCTAssertEqual(history.samples[1].droppedFPS, 0)
        XCTAssertFalse(history.hasRenderedFrames)
    }

    private func diagnosticsSnapshot(input: Double, shown: Int64, late: Int64) -> PlaybackDiagnosticsSnapshot {
        PlaybackDiagnosticsSnapshot(engine: .vlc, currentTime: 0, duration: 0, isPlaying: true, isSeekable: true, inputBytesRead: 0, inputBitrate: input, demuxBytesRead: 0, demuxBitrate: input, demuxCorrupted: 0, demuxDiscontinuity: 0, decodedVideo: shown, decodedAudio: 0, displayedPictures: shown, latePictures: late, lostPictures: 0, playedAudioBuffers: 0, lostAudioBuffers: 0, videoResolution: nil, videoFrameRate: nil, videoCodec: nil, audioTitle: nil, audioLanguageCode: nil, audioCodec: nil, subtitleTitle: nil, subtitleLanguageCode: nil, subtitleCodec: nil)
    }
}
