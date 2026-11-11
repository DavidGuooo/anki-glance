import Foundation
import Testing
@testable import GlanceCore

struct MediaCacheTests {
    @Test func findsLocalImagesInCardHtml() {
        let html = #"<img src="a.png"> <IMG class=x src='b c.jpg'> <img src="d%20e.gif"> <img src="f&amp;g.png">"#
            + #"<img src="https://example.com/x.png"> <img src="data:image/png;base64,AA"> <img src="">"#
        #expect(MediaCache.filenames(in: html) == ["a.png", "b c.jpg", "d e.gif", "f&g.png"])
    }

    @Test func preloadFillsTheCache() async throws {
        let fetched = Counter()
        let cache = MediaCache { name in await fetched.add(name); return Data(name.utf8) }
        await cache.preload(html: #"<img src="a.png"><img src="b.png">"#)
        _ = try await cache.data(for: "a.png")
        #expect(await fetched.names.sorted() == ["a.png", "b.png"])
    }
}

private actor Counter {
    private(set) var names: [String] = []
    func add(_ name: String) { names.append(name) }
}
