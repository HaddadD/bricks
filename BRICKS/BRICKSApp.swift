import SwiftUI

@main
struct BRICKSApp: App {
    @StateObject private var settings = Settings()
    @StateObject private var model = GameModel()

    var body: some Scene {
        WindowGroup {
            root
                // Drives the trait collection, which is what every adaptive colour
                // in Theme resolves against.
                .preferredColorScheme(settings.colorScheme)
                // Switching the widget back on shows the game straight away, not after
                // the next move.
                .onReceive(settings.$widgetEnabled) { on in if on { model.publishWidget() } }
        }
        #if os(macOS)
        .defaultSize(width: 1040, height: 760)
        .windowResizability(.contentMinSize)
        #elseif os(visionOS)
        .defaultSize(width: 1180, height: 820)
        #endif
        #if os(macOS) || os(iOS) || os(visionOS)
        .commands { GameCommands() }
        #endif
    }

    @ViewBuilder
    private var root: some View {
        #if os(watchOS)
        WatchGameView(settings: settings, model: model)
        #elseif os(iOS) && DEBUG
        if ProcessInfo.processInfo.arguments.contains("-widgetPreview") {
            WidgetPreviewScreen()
        } else {
            GameView(settings: settings, model: model)
        }
        #elseif os(macOS)
        GameView(settings: settings, model: model)
            // Below this the wide layout's power-up chips get cramped.
            .frame(minWidth: 640, minHeight: 560)
        #else
        GameView(settings: settings, model: model)
        #endif
    }
}

#if os(macOS) || os(iOS) || os(visionOS)
/// The game's menu items: the Mac menu bar, and the shortcuts list on an iPad with a
/// keyboard.
private struct GameCommands: Commands {
    @FocusedValue(\.gameActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Game") { actions?.newGame() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Move") { actions?.undo() }
                .keyboardShortcut("z")
                .disabled(actions?.canUndo != true)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { actions?.showSettings() }
                .keyboardShortcut(",")
                .disabled(actions == nil)
        }
    }
}
#endif
