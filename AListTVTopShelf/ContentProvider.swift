import TVServices

/// Shows the Gallery's Watching shelf above the app's icon. The remote's Play
/// button resumes a card's file right away; selecting it opens the title.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let snapshot = TopShelfWatchingStore.shared()?.snapshot(), !snapshot.items.isEmpty else {
            completionHandler(nil)
            return
        }
        let items = snapshot.items.map { entry -> TVTopShelfSectionedItem in
            let item = TVTopShelfSectionedItem(identifier: entry.path)
            item.title = [entry.title, entry.subtitle].compactMap { $0 }.joined(separator: " · ")
            item.imageShape = .hdtv
            item.playbackProgress = entry.progress
            item.setImageURL(entry.imageURL, for: [.screenScale1x, .screenScale2x])
            item.playAction = TVTopShelfAction(url: TopShelfLink.play(path: entry.path).url)
            item.displayAction = TVTopShelfAction(url: TopShelfLink.show(path: entry.path).url)
            return item
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Watching"
        completionHandler(TVTopShelfSectionedContent(sections: [section]))
    }
}
