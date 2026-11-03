import Foundation
import XCTest
@testable import AListTV

final class TopShelfWatchingTests: XCTestCase {
    func testLinksRoundTripPathsWithSpacesAndCJK() {
        let path = "/kk/来自：分享/鬼.子.来.了 (2000) 1080P REMUX/鬼子来了 (2000).mkv"
        XCTAssertEqual(TopShelfLink(url: TopShelfLink.play(path: path).url), .play(path: path))
        XCTAssertEqual(TopShelfLink(url: TopShelfLink.show(path: path).url), .show(path: path))
    }

    func testRejectsForeignOrIncompleteLinks() {
        XCTAssertNil(TopShelfLink(url: URL(string: "https://play?path=/a.mkv")!))
        XCTAssertNil(TopShelfLink(url: URL(string: "alisttv://delete?path=/a.mkv")!))
        XCTAssertNil(TopShelfLink(url: URL(string: "alisttv://play")!))
    }

    func testSaveReportsChangesAndClears() {
        let suite = "TopShelfWatchingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TopShelfWatchingStore(defaults: defaults)
        let item = TopShelfWatchingItem(path: "/a.mkv", name: "a.mkv", size: 1, title: "A", subtitle: nil, imageURL: nil, progress: 0.5)
        let snapshot = TopShelfWatchingSnapshot(baseURL: "https://alist.example", username: "alice", items: [item])

        XCTAssertTrue(store.save(snapshot))
        XCTAssertFalse(store.save(snapshot))
        XCTAssertEqual(store.snapshot(), snapshot)
        XCTAssertTrue(store.save(nil))
        XCTAssertNil(store.snapshot())
    }
}
