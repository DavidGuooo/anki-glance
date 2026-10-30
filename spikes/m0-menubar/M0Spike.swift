// PROTOTYPE — M0 spike for Anki Glance. Throwaway: answers questions, not production code.
// Questions (docs/DESIGN.md, Milestone M0):
//   1. Does the menu bar stay visible over a full-screen app while the panel is open? NSPanel ("P") vs MenuBarExtra ("M").
//   2. Do clicks and keys reach each panel?
//   3. Does AnkiConnect collection.sync make Anki show a window or switch Spaces?
import AppKit
import SwiftUI

// MARK: - Logging and probes

@MainActor final class Probe: ObservableObject {
    static let shared = Probe()
    @Published var lines: [String] = []
    @Published var menuBar = "?"

    func append(_ line: String) {
        lines.append(line)
        if lines.count > 40 { lines.removeFirst(lines.count - 40) }
    }
}

let stamp: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

func log(_ message: String) {
    let line = "\(stamp.string(from: Date())) \(message)"
    print(line)
    fflush(stdout)
    Task { @MainActor in Probe.shared.append(line) }
}

func frontmost() -> String {
    NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
}

/// Menu bar (layer 24) and status item (layer 25) windows that are on screen, plus Anki's on-screen windows.
func windowSnapshot() -> String {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return "window list unavailable"
    }
    func describe(_ w: [String: Any]) -> String {
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        return "\(owner)@y\(Int(b["Y"] ?? -1))h\(Int(b["Height"] ?? -1))"
    }
    let layer = { (w: [String: Any]) in w[kCGWindowLayer as String] as? Int ?? -1 }
    let menuBars = list.filter { layer($0) == 24 }.map(describe)
    let statusItems = list.filter { layer($0) == 25 }.count
    let anki = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "Anki" && layer($0) == 0 }.map(describe)
    return "menubar=\(menuBars) statusItems=\(statusItems) ankiWindows=\(anki)"
}

@MainActor func startMonitors() {
    var last = ""
    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
        MainActor.assumeIsolated {
            let now = windowSnapshot()
            if now != last {
                last = now
                Probe.shared.menuBar = now
                log("windows: \(now)")
            }
        }
    }
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
        let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "?"
        log("frontmost app -> \(app)")
    }
    center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
        log("ACTIVE SPACE CHANGED (front=\(frontmost()))")
    }
    log("spike started, front=\(frontmost())")
}

func syncNow(from variant: String) async {
    log("\(variant): sync start, front=\(frontmost())")
    var request = URLRequest(url: URL(string: "http://127.0.0.1:8765/api/v1")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"collection.sync","params":{}}"#.utf8)
    request.timeoutInterval = 120
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        log("\(variant): sync reply \(String(decoding: data, as: UTF8.self).prefix(300)), front=\(frontmost())")
    } catch {
        log("\(variant): sync error \(error.localizedDescription)")
    }
}

// MARK: - Shared probe view

struct ProbeView: View {
    let variant: String
    var close: () -> Void = {}
    @ObservedObject private var probe = Probe.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROTOTYPE M0 — \(variant)").font(.headline)
            Text(probe.menuBar).font(.caption2.monospaced()).lineLimit(3)
            HStack {
                Button("Click test") { log("\(variant): button clicked, front=\(frontmost())") }
                Button("Sync now") { Task { await syncNow(from: variant) } }
                Button("Close") { close() }
            }
            Text("Type keys here (1–4, space, esc)").font(.caption)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(probe.lines.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced())
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 380, height: 320)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            log("\(variant): key \(press.characters.debugDescription) (front=\(frontmost()), appActive=\(NSApp.isActive))")
            if press.key == .escape { close() }
            return .handled
        }
        .onAppear {
            focused = true
            log("\(variant): appeared, front=\(frontmost()), appActive=\(NSApp.isActive)")
        }
    }
}

// MARK: - Variant P: NSStatusItem + non-activating NSPanel

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panel: KeyPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "P"
        item.button?.target = self
        item.button?.action = #selector(toggle)

        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
                         styleMask: [.nonactivatingPanel, .borderless],
                         backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: ProbeView(variant: "NSPanel", close: { [weak self] in self?.hide() }))

        MainActor.assumeIsolated { startMonitors() }
    }

    @objc private func toggle() {
        if panel.isVisible { hide(); return }
        if let frame = item.button?.window?.frame {
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 380, y: frame.minY - 4))
        }
        panel.makeKeyAndOrderFront(nil)
        item.button?.highlight(true)
        log("NSPanel: opened, key=\(panel.isKeyWindow), appActive=\(NSApp.isActive), front=\(frontmost())")
    }

    private func hide() {
        panel.orderOut(nil)
        item.button?.highlight(false)
        log("NSPanel: closed, front=\(frontmost())")
    }
}

// MARK: - Variant M: SwiftUI MenuBarExtra(.window)

@main
struct M0SpikeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("M") {
            ProbeView(variant: "MenuBarExtra")
        }
        .menuBarExtraStyle(.window)
    }
}
