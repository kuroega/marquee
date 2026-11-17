import XCTest
@testable import AListTV

final class GalleryShowEpisodesThroughTests: XCTestCase {
    private func episode(_ season: Int, _ number: Int) -> GalleryEpisode {
        let path = "/TV/Dark/Dark.S\(season)E\(number).mkv"
        let file = LibraryFile(path: path, name: (path as NSString).lastPathComponent, size: 1, modified: nil, parsed: MediaNameParser.parse(path: path))
        return GalleryEpisode(season: season, episode: number, file: file)
    }

    private var show: GalleryShow {
        // Ordered by season, then episode, as the catalog builds it.
        GalleryShow(
            id: "show|dark", title: "Dark", genreIDs: [],
            episodes: [episode(0, 1), episode(0, 2), episode(1, 1), episode(1, 2), episode(1, 3), episode(2, 1), episode(2, 2)],
            addedAt: .distantPast
        )
    }

    private func codes(_ episodes: [GalleryEpisode]) -> [String] { episodes.map(\.code) }

    func testARegularEpisodeTakesEveryEarlierRegularEpisodeButNoSpecials() {
        XCTAssertEqual(codes(show.episodes(through: episode(2, 1))), ["S1 · E1", "S1 · E2", "S1 · E3", "S2 · E1"])
        XCTAssertEqual(codes(show.episodes(through: episode(1, 1))), ["S1 · E1"])
    }

    func testASpecialTakesOnlyTheSpecialsBeforeIt() {
        XCTAssertEqual(codes(show.episodes(through: episode(0, 2))), ["S0 · E1", "S0 · E2"])
    }
}

final class PlaybackWatchedBatchTests: XCTestCase {
    func testMarkingManyFilesDropsTheirResumePointsAndKeepsOtherHistory() {
        let suite = "PlaybackWatchedBatchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackProgressStore(defaults: defaults)
        let identity = { (path: String) in PlaybackProgressIdentity(baseURL: "b", username: "u", virtualPath: path) }
        store.update(identity: identity("/a.mkv"), position: 300, duration: 1_000)
        store.update(identity: identity("/other.mkv"), position: 300, duration: 1_000)
        store.setWatched(true, identity: identity("/older.mkv"))

        store.setWatched(true, identities: [identity("/a.mkv"), identity("/b.mkv"), identity("/a.mkv")])

        XCTAssertEqual(store.watchedRecords().map(\.identity.virtualPath), ["/a.mkv", "/b.mkv", "/older.mkv"])
        XCTAssertNil(store.record(for: identity("/a.mkv")))
        XCTAssertNotNil(store.record(for: identity("/other.mkv")))

        store.setWatched(false, identities: [identity("/a.mkv"), identity("/b.mkv")])
        XCTAssertEqual(store.watchedRecords().map(\.identity.virtualPath), ["/older.mkv"])
    }
}

@MainActor
final class GalleryMarkEarlierWatchedTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let baseURL = URL(string: "https://media.example.test")!

    override func setUp() async throws {
        directory = try GalleryFixtures.temporaryDirectory()
        suiteName = "gallery-mark-earlier-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    func testMarkThisAndEarlierOffersOnlyUnwatchedEpisodesAndNeedsAnEarlierOne() async throws {
        let server = FakeLibraryServer()
        await server.setFolder("/TV", [GalleryFixtures.folder("/TV/Dark")])
        await server.setFolder("/TV/Dark", [GalleryFixtures.folder("/TV/Dark/Season 1"), GalleryFixtures.folder("/TV/Dark/Season 2")])
        let paths = [
            "/TV/Dark/Season 1/Dark.S01E01.mkv", "/TV/Dark/Season 1/Dark.S01E02.mkv", "/TV/Dark/Season 1/Dark.S01E03.mkv",
            "/TV/Dark/Season 2/Dark.S02E01.mkv", "/TV/Dark/Season 2/Dark.S02E02.mkv"
        ]
        await server.setFolder("/TV/Dark/Season 1", paths[0 ..< 3].map { GalleryFixtures.video($0) })
        await server.setFolder("/TV/Dark/Season 2", paths[3...].map { GalleryFixtures.video($0) })
        let store = GalleryLibraryStore(baseURL: baseURL, username: "alice", defaults: defaults, directory: directory)
        store.setRoots(["/TV"])
        let progress = PlaybackProgressStore(defaults: defaults)
        let identity = { (path: String) in PlaybackProgressIdentity(baseURL: self.baseURL.absoluteString, username: "alice", virtualPath: path) }
        progress.setWatched(true, identity: identity(paths[1]))
        progress.update(identity: identity(paths[2]), position: 600, duration: 3_000)

        let viewModel = GalleryViewModel(
            api: server, store: store, progressStore: progress,
            recentItemsStore: RecentItemsStore(defaults: defaults),
            baseURL: baseURL, username: "alice", tmdbAPIKey: nil
        )
        viewModel.onAppear()
        for _ in 0 ..< 400 where !(viewModel.phase == .ready && viewModel.catalog.videoCount == 5) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let (show, target) = try XCTUnwrap(viewModel.catalog.episode(forPath: paths[3]))

        // The watched S1 E2 is skipped; the half-watched S1 E3 is included.
        let pending = viewModel.unwatchedEpisodes(through: target, in: show)
        XCTAssertEqual(pending.map(\.path), [paths[0], paths[2], paths[3]])

        // The first episode has nothing before it, so only the plain mark applies.
        let first = try XCTUnwrap(viewModel.catalog.episode(forPath: paths[0])?.episode)
        XCTAssertTrue(viewModel.unwatchedEpisodes(through: first, in: show).isEmpty)

        viewModel.setWatched(true, paths: pending.map(\.path))
        XCTAssertEqual(paths.map { viewModel.watch.isWatched($0) }, [true, true, true, true, false])
        XCTAssertEqual(viewModel.status(paths[2]), .watched)
        XCTAssertTrue(viewModel.unwatchedEpisodes(through: target, in: show).isEmpty)
    }
}
