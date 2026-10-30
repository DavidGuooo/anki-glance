import GlanceCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Renders Anki's card HTML and note CSS as-is, with a thin layer on top for the panel's
/// transparent background and dark mode. Images load through `anki-media://` from AnkiConnect.
struct CardWebView: NSViewRepresentable {
    let html: String
    let media: MediaCache
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(MediaSchemeHandler(media: media), forURLScheme: MediaSchemeHandler.scheme)
        let view = PassiveWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let page = Self.page(for: html, dark: colorScheme == .dark)
        guard page != context.coordinator.loadedPage else { return }
        context.coordinator.loadedPage = page
        view.loadHTMLString(page, baseURL: URL(string: "\(MediaSchemeHandler.scheme)://media/"))
    }

    static func page(for html: String, dark: Bool) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><meta name="color-scheme" content="\(dark ? "dark" : "light")">
        <style>
        html, body { margin: 0; background: transparent !important; }
        /* Note types are styled for a full window; scale them down to the panel. */
        body { zoom: 0.8; }
        .card { color: CanvasText !important; background: transparent !important; padding: 12px 14px; overflow-wrap: anywhere; }
        img { max-width: 100%; height: auto; }
        hr#answer { border: none; border-top: 1px solid color-mix(in srgb, CanvasText 20%, transparent); margin: 10px 0; }
        pre { text-align: left; white-space: pre-wrap; }
        </style></head>
        <body class="card\(dark ? " nightMode night_mode" : "")">\(html)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedPage: String?

        /// Only the card itself loads in the panel; links open in the default browser.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            NSWorkspace.shared.open(url)
            return .cancel
        }
    }
}

/// Keeps keyboard focus on the panel so Space and 1–4 always reach it, even after clicking the card.
final class PassiveWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}

@MainActor
final class MediaSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "anki-media"
    private let media: MediaCache
    private var stopped: Set<ObjectIdentifier> = []

    init(media: MediaCache) {
        self.media = media
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let id = ObjectIdentifier(task)
        Task {
            do {
                let data = try await media.data(for: url.lastPathComponent)
                guard !stopped.contains(id) else { return }
                let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil))
                task.didReceive(data)
                task.didFinish()
            } catch {
                guard !stopped.contains(id) else { return }
                task.didFailWithError(error)
            }
            stopped.remove(id)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        stopped.insert(ObjectIdentifier(task))
    }
}
