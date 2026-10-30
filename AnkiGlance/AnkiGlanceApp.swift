import SwiftUI

@main
struct AnkiGlanceApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--preview-panel") { PanelPreviewWindow.show(model: model) }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(model)
        } label: {
            MenuBarLabel(totalDue: model.panel.totalDue)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let totalDue: Int?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "rectangle.on.rectangle.angled")
            if let totalDue, totalDue > 0 {
                Text("\(totalDue)")
            }
        }
    }
}
