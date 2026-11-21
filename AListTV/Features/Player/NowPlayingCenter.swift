import AVFoundation
import MediaPlayer
import UIKit

/// What the system Now Playing card shows for the current file.
struct NowPlayingMetadata: Equatable, Sendable {
    let title: String
    /// Episode code or year, shown under the title.
    let subtitle: String?
    /// Landscape artwork first (the iPhone remote card is 16:9), then a poster.
    let artworkURLs: [URL]

    /// A file the Gallery has not matched: its name without the extension,
    /// under its folder's name.
    static func fallback(name: String, path: String?) -> NowPlayingMetadata {
        let title = (name as NSString).deletingPathExtension
        let folder = path.map { AListPath.parent(of: $0) }.flatMap { $0 == "/" ? nil : $0.split(separator: "/").last.map(String.init) }
        return NowPlayingMetadata(title: title.isEmpty ? name : title, subtitle: folder, artworkURLs: [])
    }
}

/// The playback state handed to the Now Playing card.
struct NowPlayingTiming: Equatable, Sendable {
    let elapsed: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool

    /// The system extrapolates elapsed time from the rate, so an update is
    /// only needed when the rate or length changes or the clock drifts.
    func needsUpdate(from previous: NowPlayingTiming?, now: TimeInterval, publishedAt: TimeInterval) -> Bool {
        guard let previous else { return true }
        if previous.isPlaying != isPlaying || abs(previous.duration - duration) > 0.5 { return true }
        let expected = previous.elapsed + (previous.isPlaying ? now - publishedAt : 0)
        return abs(expected - elapsed) > 1.5
    }
}

/// Remote actions from the Siri Remote's media keys, the iPhone/iPad
/// Apple TV Remote and Control Center.
@MainActor
protocol NowPlayingCommandHandling: AnyObject {
    func nowPlayingPlay()
    func nowPlayingPause()
    func nowPlayingTogglePlayPause()
    func nowPlayingSkip(by seconds: TimeInterval)
    func nowPlayingSeek(to seconds: TimeInterval)
}

/// Publishes the current file to `MPNowPlayingInfoCenter` and routes
/// `MPRemoteCommandCenter` commands back to the player. Neither VLCKit nor a
/// bare `AVPlayerLayer` does this on its own, so without it the iPhone remote
/// card shows no title, artwork or progress.
@MainActor
final class NowPlayingCenter {
    static let skipInterval: TimeInterval = 10

    private let infoCenter: MPNowPlayingInfoCenter
    private let commandCenter: MPRemoteCommandCenter
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private weak var handler: NowPlayingCommandHandling?
    private var info: [String: Any] = [:]
    private var metadata: NowPlayingMetadata?
    private var timing: NowPlayingTiming?
    private var timingPublishedAt: TimeInterval = 0
    private var artworkTask: Task<Void, Never>?

    init(infoCenter: MPNowPlayingInfoCenter = .default(), commandCenter: MPRemoteCommandCenter = .shared()) {
        self.infoCenter = infoCenter
        self.commandCenter = commandCenter
    }

    /// Starts showing `metadata`; the previous file's card is replaced.
    func begin(_ metadata: NowPlayingMetadata, handler: NowPlayingCommandHandling) {
        self.handler = handler
        registerCommands()
        activateAudioSession()
        guard metadata != self.metadata else { return }
        self.metadata = metadata
        timing = nil
        artworkTask?.cancel()
        info = [
            MPMediaItemPropertyTitle: metadata.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
        ]
        if let subtitle = metadata.subtitle { info[MPMediaItemPropertyArtist] = subtitle }
        infoCenter.nowPlayingInfo = info
        loadArtwork(for: metadata)
    }

    func update(_ timing: NowPlayingTiming, force: Bool = false) {
        guard metadata != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || timing.needsUpdate(from: self.timing, now: now, publishedAt: timingPublishedAt) else { return }
        self.timing = timing
        timingPublishedAt = now
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, timing.elapsed)
        info[MPNowPlayingInfoPropertyPlaybackRate] = timing.isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        if timing.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = timing.duration
            info[MPNowPlayingInfoPropertyPlaybackProgress] = PlaybackPresentation.clampedProgressFraction(timing.elapsed, duration: timing.duration)
        }
        infoCenter.nowPlayingInfo = info
    }

    /// Removes the card and stops taking remote commands.
    func end() {
        artworkTask?.cancel()
        artworkTask = nil
        metadata = nil
        timing = nil
        info = [:]
        handler = nil
        infoCenter.nowPlayingInfo = nil
        unregisterCommands()
    }

    private func loadArtwork(for metadata: NowPlayingMetadata) {
        guard !metadata.artworkURLs.isEmpty else { return }
        artworkTask = Task { [weak self] in
            for url in metadata.artworkURLs {
                guard let image = await ArtworkPipeline.shared.image(for: url) else { continue }
                guard !Task.isCancelled, let self, self.metadata == metadata else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.info[MPMediaItemPropertyArtwork] = artwork
                self.infoCenter.nowPlayingInfo = self.info
                return
            }
        }
    }

    /// The remote card only appears for an app that owns playback audio.
    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    private func registerCommands() {
        guard commandTargets.isEmpty else { return }
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        add(commandCenter.playCommand) { $0.nowPlayingPlay() }
        add(commandCenter.pauseCommand) { $0.nowPlayingPause() }
        add(commandCenter.togglePlayPauseCommand) { $0.nowPlayingTogglePlayPause() }
        add(commandCenter.skipForwardCommand) { handler, event in
            handler.nowPlayingSkip(by: (event as? MPSkipIntervalCommandEvent)?.interval ?? Self.skipInterval)
        }
        add(commandCenter.skipBackwardCommand) { handler, event in
            handler.nowPlayingSkip(by: -((event as? MPSkipIntervalCommandEvent)?.interval ?? Self.skipInterval))
        }
        add(commandCenter.changePlaybackPositionCommand) { handler, event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return }
            handler.nowPlayingSeek(to: event.positionTime)
        }
    }

    private func add(_ command: MPRemoteCommand, _ action: @escaping @MainActor (NowPlayingCommandHandling) -> Void) {
        add(command) { handler, _ in action(handler) }
    }

    private func add(_ command: MPRemoteCommand, _ action: @escaping @MainActor (NowPlayingCommandHandling, MPRemoteCommandEvent) -> Void) {
        command.isEnabled = true
        // MediaPlayer calls targets on the main thread; hop there if it ever does not.
        let target = command.addTarget { [weak self] event in
            guard Thread.isMainThread else {
                DispatchQueue.main.async { MainActor.assumeIsolated { if let handler = self?.handler { action(handler, event) } } }
                return .success
            }
            return MainActor.assumeIsolated {
                guard let handler = self?.handler else { return .noActionableNowPlayingItem }
                action(handler, event)
                return .success
            }
        }
        commandTargets.append((command, target))
    }

    private func unregisterCommands() {
        for (command, target) in commandTargets {
            command.removeTarget(target)
            command.isEnabled = false
        }
        commandTargets = []
    }
}
