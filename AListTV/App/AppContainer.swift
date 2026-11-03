import Combine
import Foundation

@MainActor
final class AppContainer: ObservableObject {
    enum Route {
        case connection
        case browser
    }

    @Published private(set) var route: Route = .connection
    @Published private(set) var browserViewModel: BrowserViewModel?
    @Published private(set) var playerCoordinator: PlayerCoordinator?
    @Published private(set) var recentsViewModel: RecentsViewModel?
    @Published private(set) var galleryViewModel: GalleryViewModel?
    @Published private(set) var logoutError: String?
    @Published private(set) var isRestoringSession = true


    let connectionViewModel: ConnectionViewModel
    /// Backing store for view preferences such as the home mode and layout.
    let appStorage: UserDefaults

    private let controllerFactory: @MainActor () -> any PlayerControlling
    private let dolbyVisionControllerFactory: @MainActor () -> (any PlayerControlling)?
    private let subtitleDataLoader: @Sendable (URL) async throws -> Data
    private let subtitleAppearanceStore: SubtitleAppearanceStore
    private let playbackProgressStore: PlaybackProgressStore
    private let playbackSettingsStore: PlaybackSettingsStore
    private let recentItemsStore: RecentItemsStore
    private let tmdbAPIKey: String?
    private let galleryCacheDirectory: URL?
    private let topShelf: TopShelfWatchingStore?
    /// A Top Shelf card's request, held until a session is active.
    private var pendingLink: TopShelfLink?
    private var didAttemptRestore = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let credentialStore: any CredentialStore
        let preferences: ConnectionPreferences
        let subtitleAppearanceStore: SubtitleAppearanceStore
        let clientFactory: AListClientFactory
        let controllerFactory: @MainActor () -> any PlayerControlling
        // Real servers only: fixtures never offer a Dolby Vision stream.
        var dolbyVisionControllerFactory: @MainActor () -> (any PlayerControlling)? = {
            NativePlayerControllerAdapter.isSupported ? NativePlayerControllerAdapter() : nil
        }
        let subtitleDataLoader: @Sendable (URL) async throws -> Data
        let playbackProgressStore: PlaybackProgressStore
        let playbackSettingsStore: PlaybackSettingsStore
        let recentItemsStore: RecentItemsStore
        let appStorage: UserDefaults
        var tmdbAPIKey = TMDBConfiguration.apiKey()
        var galleryCacheDirectory: URL?
        var topShelf = TopShelfWatchingStore.shared()

#if DEBUG
        if arguments.contains("ui-testing") {
            let defaults = UserDefaults(suiteName: "com.alist.tv.ui-testing")!
            defaults.removePersistentDomain(forName: "com.alist.tv.ui-testing")
            let memoryStore = InMemoryCredentialStore()
            let fixtureAPI = FixtureAListAPI()
            credentialStore = memoryStore
            preferences = ConnectionPreferences(defaults: defaults)
            subtitleAppearanceStore = SubtitleAppearanceStore(defaults: defaults)
            playbackProgressStore = PlaybackProgressStore(defaults: defaults)
            playbackSettingsStore = PlaybackSettingsStore(defaults: defaults)
            recentItemsStore = RecentItemsStore(defaults: defaults)
            appStorage = defaults
            clientFactory = { _, _ in fixtureAPI }
            controllerFactory = { FixturePlayerController(autoCompletesPlayback: arguments.contains("ui-testing-autoplay")) }
            dolbyVisionControllerFactory = { nil }
            subtitleDataLoader = FixtureSubtitleDataLoader.load
            // UI tests stay offline and never reuse a real library index.
            tmdbAPIKey = nil
            galleryCacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("gallery-ui-testing-\(UUID().uuidString)")
            topShelf = nil
        } else {
            let sessionStore = SessionCredentialStore(backing: KeychainCredentialStore())
            credentialStore = sessionStore
            preferences = ConnectionPreferences()
            subtitleAppearanceStore = SubtitleAppearanceStore()
            playbackProgressStore = PlaybackProgressStore()
            playbackSettingsStore = PlaybackSettingsStore()
        recentItemsStore = RecentItemsStore()
        appStorage = .standard
            clientFactory = { baseURL, clientID in
                AListClient(
                    baseURL: baseURL,
                    clientID: clientID,
                    tokenProvider: { sessionStore.currentToken }
                )
            }
            controllerFactory = { VLCPlayerControllerAdapter() }
            subtitleDataLoader = PlayerCoordinator.loadSubtitleData
        }
#else
        let sessionStore = SessionCredentialStore(backing: KeychainCredentialStore())
        credentialStore = sessionStore
        preferences = ConnectionPreferences()
        subtitleAppearanceStore = SubtitleAppearanceStore()
        playbackProgressStore = PlaybackProgressStore()
        playbackSettingsStore = PlaybackSettingsStore()
        recentItemsStore = RecentItemsStore()
        appStorage = .standard
        clientFactory = { baseURL, clientID in
            AListClient(
                baseURL: baseURL,
                clientID: clientID,
                tokenProvider: { sessionStore.currentToken }
            )
        }
        controllerFactory = { VLCPlayerControllerAdapter() }
        subtitleDataLoader = PlayerCoordinator.loadSubtitleData
#endif

        self.controllerFactory = controllerFactory
        self.dolbyVisionControllerFactory = dolbyVisionControllerFactory
        self.subtitleDataLoader = subtitleDataLoader
        self.subtitleAppearanceStore = subtitleAppearanceStore
        self.playbackProgressStore = playbackProgressStore
        self.playbackSettingsStore = playbackSettingsStore
        self.recentItemsStore = recentItemsStore
        self.appStorage = appStorage
        self.tmdbAPIKey = tmdbAPIKey
        self.galleryCacheDirectory = galleryCacheDirectory
        self.topShelf = topShelf
        connectionViewModel = ConnectionViewModel(
            preferences: preferences,
            credentialStore: credentialStore,
            clientFactory: clientFactory
        )
    }

    func restoreSession() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        defer { isRestoringSession = false }
        await connectionViewModel.restore()
        activateConnectedSessionIfAvailable()
    }

    func retrySessionRecovery() async {
        await connectionViewModel.restore()
        activateConnectedSessionIfAvailable()
    }

    func submit(serverURL: String, username: String, password: String) async {
        await connectionViewModel.submit(serverURL: serverURL, username: username, password: password)
        activateConnectedSessionIfAvailable()
    }

    func submitOTP(_ code: String) async {
        await connectionViewModel.submitOTP(code)
        activateConnectedSessionIfAvailable()
    }
    func logout() {
        do {
            try connectionViewModel.clearSession()
        } catch {
            logoutError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        clearActiveSession()
    }

    func dismissLogoutError() {
        logoutError = nil
    }

    /// Handles a Top Shelf card's Play (resume now) or select (show the title).
    func open(_ url: URL) {
        guard let link = TopShelfLink(url: url) else { return }
        pendingLink = link
        openPendingLink()
    }

    private func openPendingLink() {
        guard let link = pendingLink, route == .browser,
              let player = playerCoordinator, let gallery = galleryViewModel,
              let connection = connectionViewModel.activeConnection else { return }
        pendingLink = nil
        // Cards only ever stand for the signed-in account's files.
        guard let snapshot = topShelf?.snapshot(),
              snapshot.baseURL == connection.baseURL.absoluteString, snapshot.username == connection.username,
              let item = snapshot.items.first(where: { $0.path == link.path }) else { return }
        switch link {
        case .play:
            let object = AListObject(virtualPath: item.path, name: item.name, size: item.size, isDirectory: false, type: AListFileType.video.rawValue)
            Task { await player.play(object: object, resuming: true) }
        case .show:
            player.isPresented = false
            appStorage.set(HomeMode.gallery.rawValue, forKey: HomeMode.storageKey)
            gallery.reveal(path: item.path)
        }
    }



    private func activateConnectedSessionIfAvailable() {
        guard connectionViewModel.state == .connected,
              let api = connectionViewModel.activeAPI,
              let connection = connectionViewModel.activeConnection else { return }

        let player = PlayerCoordinator(
            api: api,
            controller: controllerFactory(),
            dolbyVisionController: dolbyVisionControllerFactory(),
            progressStore: playbackProgressStore,
            subtitleAppearanceStore: subtitleAppearanceStore,
            playbackSettingsStore: playbackSettingsStore,
            skipSegmentsStore: SkipSegmentsStore(defaults: appStorage),
            baseURL: connection.baseURL,
            username: connection.username,
            onUnauthorized: { [weak self] in self?.handleUnauthorized() },
            onPlaybackStarted: { [weak self] object in self?.recentsViewModel?.recordOpen(object) },
            subtitleDataLoader: subtitleDataLoader
        )
        playerCoordinator = player
        recentsViewModel = RecentsViewModel(
            store: recentItemsStore,
            progressStore: playbackProgressStore,
            baseURL: connection.baseURL,
            username: connection.username,
            onOpen: { [weak player] object in await player?.play(object: object) }
        )
        browserViewModel = BrowserViewModel(
            api: api,
            onPlay: { [weak player] object in await player?.play(object: object) },
            onUnauthorized: { [weak self] in self?.handleUnauthorized() }
        )
        galleryViewModel = GalleryViewModel(
            api: api,
            store: GalleryLibraryStore(baseURL: connection.baseURL, username: connection.username, defaults: appStorage, directory: galleryCacheDirectory),
            progressStore: playbackProgressStore,
            recentItemsStore: recentItemsStore,
            baseURL: connection.baseURL,
            username: connection.username,
            tmdbAPIKey: tmdbAPIKey,
            topShelf: topShelf,
            onPlay: { [weak player] object in await player?.play(object: object) },
            onUnauthorized: { [weak self] in self?.handleUnauthorized() }
        )
        route = .browser
        openPendingLink()
    }

    private func handleUnauthorized() {
        try? connectionViewModel.clearSession()
        clearActiveSession()
    }

    private func clearActiveSession() {
        playerCoordinator?.playerDidDisappear()
        playerCoordinator = nil
        browserViewModel = nil
        recentsViewModel = nil
        galleryViewModel = nil
        route = .connection
        topShelf?.publish(nil)
    }
}
