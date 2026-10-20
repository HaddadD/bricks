import SwiftUI

@main
struct BRICKSApp: App {
    @StateObject private var settings = Settings()

    var body: some Scene {
        WindowGroup {
            GameView(settings: settings)
                // Drives the trait collection, which is what every adaptive colour
                // in Theme resolves against.
                .preferredColorScheme(settings.colorScheme)
        }
    }
}
