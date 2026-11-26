import SwiftUI

@main
struct BRICKSApp: App {
    @StateObject private var settings = Settings()
    @StateObject private var model = GameModel()
    @StateObject private var updates = UpdateCheck()
    @StateObject private var progress = PlayerProgress()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            root
                // Drives the trait collection, which is what every adaptive colour
                // in Theme resolves against.
                .preferredColorScheme(settings.colorScheme)
                // Switching the widget back on shows the game straight away, not after
                // the next move.
                .onReceive(settings.$widgetEnabled) { on in if on { model.publishWidget() } }
                // An App Store copy that's behind the store can't be played until it's
                // updated.
                .disabled(updates.requiredVersion != nil)
                .overlay {
                    if let version = updates.requiredVersion {
                        UpdateRequiredView(version: version)
                    }
                }
                .task { await updates.check() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task { await updates.check() }
                        GameSync.shared.refresh()
                    }
                    if phase == .background { progress.checkpoint() }
                }
                .environmentObject(progress)
                .environmentObject(GameCenter.shared)
                .onAppear(perform: start)
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

    private func start() {
        // Every device on the same iCloud account carries on the same game.
        GameSync.shared.attach(to: model)
        progress.attach(to: model)
        // The Games app's Play button: carry on, or start over if the game has ended.
        GameCenter.shared.onWantsToPlay = { [model] in if model.isGameOver { model.newGame() } }
        GameCenter.shared.signIn()
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
