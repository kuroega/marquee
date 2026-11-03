import Foundation

/// One card of the Gallery's Watching shelf, as the Top Shelf shows it.
struct TopShelfWatchingItem: Codable, Equatable, Sendable {
    let path: String
    let name: String
    let size: Int64
    /// Movie or show name.
    let title: String
    /// Episode code and time left, e.g. "S1 · E3 · 12 min left".
    let subtitle: String?
    let imageURL: URL?
    let progress: Double
}

/// The signed-in account's Watching shelf, written by the app and read by the
/// Top Shelf extension through the shared App Group.
struct TopShelfWatchingSnapshot: Codable, Equatable, Sendable {
    let baseURL: String
    let username: String
    let items: [TopShelfWatchingItem]
}

/// What a Top Shelf card asks the app to do.
enum TopShelfLink: Equatable, Sendable {
    /// The remote's Play button: start the file at its resume point.
    case play(path: String)
    /// Selecting the card: show the title in the Gallery.
    case show(path: String)

    static let scheme = "alisttv"

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else { return nil }
        switch url.host {
        case "play": self = .play(path: path)
        case "show": self = .show(path: path)
        default: return nil
        }
    }

    var path: String {
        switch self {
        case let .play(path), let .show(path): path
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .play: components.host = "play"
        case .show: components.host = "show"
        }
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url!
    }
}

struct TopShelfWatchingStore {
    static let appGroup = "group.com.alist.tv"
    static let defaultsKey = "com.alist.tv.top-shelf-watching-v1"
    private let defaults: UserDefaults
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The store in the App Group shared with the Top Shelf extension.
    static func shared() -> TopShelfWatchingStore? {
        UserDefaults(suiteName: appGroup).map(TopShelfWatchingStore.init)
    }

    func snapshot() -> TopShelfWatchingSnapshot? {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return nil }
        return try? decoder.decode(TopShelfWatchingSnapshot.self, from: data)
    }

    /// Returns whether the stored snapshot changed.
    @discardableResult
    func save(_ snapshot: TopShelfWatchingSnapshot?) -> Bool {
        guard snapshot != self.snapshot() else { return false }
        if let snapshot, let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
        return true
    }
}
