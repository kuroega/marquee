import Foundation

enum PlayerEvent: Equatable, Sendable {
    case failed(message: String)
    case paused
    case ended
    /// The stream ended before the media did (a failed HLS segment ends
    /// VLC's input), at this position.
    case interrupted(position: TimeInterval)
}

struct PlaybackSettingsStore {
    static let autoPlayNextKey = "com.alist.tv.playback-auto-next-v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAutoPlayNext() -> Bool {
        guard defaults.object(forKey: Self.autoPlayNextKey) != nil else { return true }
        return defaults.bool(forKey: Self.autoPlayNextKey)
    }

    func saveAutoPlayNext(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.autoPlayNextKey)
    }
}

struct PlaybackTrackOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let languageCode: String?
    let codec: String?
    let isSelected: Bool
}

struct ExternalSubtitleOption: Identifiable, Equatable, Sendable {
    let id: String
    let virtualPath: String
    let title: String
}

struct PlaybackResumePrompt: Equatable, Sendable {
    let position: TimeInterval
    let duration: TimeInterval
    var secondsRemaining: Int
}

enum SubtitleSelection: Equatable, Sendable {
    case off
    case embedded(trackID: String)
    case external(fileID: String)
}

/// The player rendering the current file, shown in Stats for Nerds.
enum PlaybackEngine: Equatable, Sendable {
    case vlc
    case native

    var title: String {
        switch self {
        case .vlc: "VLC (VLCKit)"
        case .native: "Apple AVPlayer (Dolby Vision)"
        }
    }
}

struct PlaybackDiagnosticsSnapshot: Equatable, Sendable {
    let engine: PlaybackEngine
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let isSeekable: Bool
    let inputBytesRead: Int64
    let inputBitrate: Double
    let demuxBytesRead: Int64
    let demuxBitrate: Double
    let demuxCorrupted: Int64
    let demuxDiscontinuity: Int64
    let decodedVideo: Int64
    let decodedAudio: Int64
    let displayedPictures: Int64
    let latePictures: Int64
    let lostPictures: Int64
    let playedAudioBuffers: Int64
    let lostAudioBuffers: Int64
    let videoResolution: String?
    let videoFrameRate: Double?
    let videoCodec: String?
    let audioTitle: String?
    let audioLanguageCode: String?
    let audioCodec: String?
    let subtitleTitle: String?
    let subtitleLanguageCode: String?
    let subtitleCodec: String?
}

/// One point on the Stats for Nerds charts. Rates come from the cumulative
/// counters of two consecutive snapshots.
struct PlaybackDiagnosticsSample: Equatable, Sendable, Identifiable {
    let id: Int
    /// Seconds since the first sample.
    let elapsed: TimeInterval
    let inputMbps: Double
    let demuxMbps: Double
    /// Pictures shown per second; nil when the player has no such counter
    /// (AVPlayer) or for the first sample.
    let renderedFPS: Double?
    /// Late plus lost pictures per second.
    let droppedFPS: Double
}

/// A rolling window of samples for the Stats for Nerds charts.
struct PlaybackDiagnosticsHistory: Equatable, Sendable {
    static let window: TimeInterval = 60
    /// AVPlayer refreshes its snapshot on every time-observer tick; one point
    /// a second keeps the lines readable.
    static let minimumInterval: TimeInterval = 0.9

    private struct Reading: Equatable, Sendable {
        let uptime: TimeInterval
        let snapshot: PlaybackDiagnosticsSnapshot
    }

    private(set) var samples: [PlaybackDiagnosticsSample] = []
    private var origin: TimeInterval?
    private var previous: Reading?
    private var nextID = 0

    var hasRenderedFrames: Bool { samples.contains { $0.renderedFPS != nil } }

    mutating func record(_ snapshot: PlaybackDiagnosticsSnapshot, at uptime: TimeInterval) {
        if let previous, uptime - previous.uptime < Self.minimumInterval { return }
        let origin = self.origin ?? uptime
        self.origin = origin

        var renderedFPS: Double?
        var droppedFPS = 0.0
        if let previous {
            let seconds = uptime - previous.uptime
            let old = previous.snapshot
            // A new media restarts VLC's counters; a negative delta is no data.
            let shown = snapshot.displayedPictures - old.displayedPictures
            if snapshot.displayedPictures > 0, shown >= 0 { renderedFPS = Double(shown) / seconds }
            let dropped = (snapshot.latePictures + snapshot.lostPictures) - (old.latePictures + old.lostPictures)
            droppedFPS = Double(max(0, dropped)) / seconds
        }

        samples.append(PlaybackDiagnosticsSample(
            id: nextID,
            elapsed: uptime - origin,
            inputMbps: max(0, snapshot.inputBitrate) * 8 / 1_000_000,
            demuxMbps: max(0, snapshot.demuxBitrate) * 8 / 1_000_000,
            renderedFPS: renderedFPS,
            droppedFPS: droppedFPS
        ))
        nextID += 1
        previous = Reading(uptime: uptime, snapshot: snapshot)
        let cutoff = uptime - origin - Self.window
        samples.removeAll { $0.elapsed < cutoff }
    }
}

enum PlaybackPresentation {
    /// VLC's default Matroska demuxer treats Cues as untrusted and, over HTTP
    /// (not fast-seekable), cannot verify them, so a seek resumes from the last
    /// keyframe it already demuxed and reads every byte up to the target: a
    /// jump to 1:14:00 in a 6.7 GB remux streamed ~5 GB through the proxy.
    /// `mkv_trusted` seeks straight to the cue; `any` falls back to the usual
    /// probe when the file is not Matroska.
    ///
    /// The extension cannot tell: WEB-DL episodes are often Matroska saved as
    /// `.mp4`, and a 29:53 seek in one read 3.2 GB (11 min) before resuming.
    /// HLS playlists are left to VLC's adaptive demuxer.
    static func vlcDemuxOption(for url: URL) -> String? {
        url.pathExtension.lowercased() == "m3u8" ? nil : ":demux=mkv_trusted,any"
    }

    static func clampedSeekTarget(_ seconds: TimeInterval, duration: TimeInterval) -> TimeInterval {
        duration > 0 ? min(max(0, seconds), duration) : max(0, seconds)
    }

    static func clampedProgressFraction(_ value: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(value / duration, 0), 1)
    }

    static func isNearEnd(currentTime: TimeInterval, duration: TimeInterval) -> Bool {
        guard currentTime.isFinite, duration.isFinite, duration > 0 else { return false }
        let tolerance = max(0.5, min(2, duration * 0.02))
        return currentTime >= duration - tolerance
    }

    static func scrubTarget(currentTime: TimeInterval, horizontalTranslation: Double, duration: TimeInterval, secondsPerPoint: TimeInterval = 1.0 / 3.0) -> TimeInterval {
        clampedSeekTarget(currentTime + horizontalTranslation * secondsPerPoint, duration: duration)
    }

    static func resumeTimeText(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", value / 3_600, (value % 3_600) / 60, value % 60)
    }

    static func trackTitle(name: String?, description: String?, language: String?, fallback: String) -> String {
        [name, description, language]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.contains("://") && !$0.contains("?") }) ?? fallback
    }

    static func frameRate(numerator: UInt32, denominator: UInt32) -> Double? {
        guard denominator != 0 else { return nil }
        return Double(numerator) / Double(denominator)
    }

    static func diagnosticBitrate(_ bytesPerSecond: Double) -> String {
        String(format: "%.2f Mbit/s", bytesPerSecond * 8 / 1_000_000)
    }

    static func diagnosticMetadata(_ title: String?, _ language: String?, _ codec: String?) -> String {
        let values = [title, language, codec].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return values.isEmpty ? "—" : values.joined(separator: " · ")
    }
}

@MainActor
protocol PlayerControlling: AnyObject {
    var events: AsyncStream<PlayerEvent> { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var isSeekable: Bool { get }
    var isBuffering: Bool { get }
    var bufferedTime: TimeInterval { get }
    var audioTracks: [PlaybackTrackOption] { get }
    var embeddedSubtitleTracks: [PlaybackTrackOption] { get }
    var selectedExternalSubtitleID: String? { get }
    var subtitleAppearance: SubtitleAppearance { get }
    var diagnostics: PlaybackDiagnosticsSnapshot? { get }

    func replaceCurrentItem(url: URL, preservingSelections: Bool)
    func play()
    func pause()
    /// Releases the current item (decoder and connections) when the
    /// coordinator switches to another player.
    func stop()
    func seek(to seconds: TimeInterval) async
    func selectAudioTrack(id: String)
    func selectEmbeddedSubtitle(id: String?)
    func selectLoadedExternalSubtitle(id: String) -> Bool
    func addExternalSubtitle(url: URL, id: String, title: String) -> Bool
    func setSubtitleAppearance(_ appearance: SubtitleAppearance)
    /// Shifts subtitles the player draws itself; positive values show them later.
    func setSubtitleDelay(_ seconds: TimeInterval)
    func setDiagnosticsEnabled(_ enabled: Bool)
}

