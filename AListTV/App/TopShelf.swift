import TVServices

extension TopShelfWatchingStore {
    /// Saves `snapshot` and has the system reload the Top Shelf if it changed.
    func publish(_ snapshot: TopShelfWatchingSnapshot?) {
        if save(snapshot) { TVTopShelfContentProvider.topShelfContentDidChange() }
    }
}
