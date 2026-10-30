import Foundation
#if os(iOS) && canImport(WidgetKit)
import WidgetKit
#endif

/// What the widget shows: a copy of the game in progress, which the app writes into the
/// App Group that it and the widget extension share. The player can switch the widget
/// off in Settings, in which case nothing is shared and the widget says so.
struct WidgetSnapshot: Codable, Equatable {
    /// Each cell's colour index, row by row; nil where the board is empty.
    var cells: [[Int?]]
    var score: Int
    var best: Int
    var isGameOver: Bool

    static let appGroup = "group.ca.wilsonlam.bricks"
    private static let snapshotKey = "bricks.widgetSnapshot"
    private static let enabledKey = "bricks.widgetEnabled"
    /// Matches the widget's `kind`, so the app can ask for it to be redrawn.
    static let widgetKind = "BricksBoard"

    private static var shared: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// On unless the player has switched it off.
    static var isEnabled: Bool {
        get { shared?.object(forKey: enabledKey) as? Bool ?? true }
        set {
            shared?.set(newValue, forKey: enabledKey)
            // Switching off takes back what was shared, not just future moves.
            if !newValue { shared?.removeObject(forKey: snapshotKey) }
            reloadWidget()
        }
    }

    static func load() -> WidgetSnapshot? {
        guard isEnabled, let data = shared?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Shares the game with the widget, if the player allows it.
    func publish() {
        guard Self.isEnabled, let data = try? JSONEncoder().encode(self) else { return }
        Self.shared?.set(data, forKey: Self.snapshotKey)
        Self.reloadWidget()
    }

    /// A made-up game for the widget gallery and placeholders.
    static let sample = WidgetSnapshot(
        cells: (0..<10).map { r in
            (0..<10).map { c -> Int? in
                switch (r, c) {
                case (2, 1...2): return 0
                case (3, 2...3): return 5
                case (4, 0...2): return 6
                case (5...6, 6...7): return 3
                case (7, 2...3): return 4
                case (8, 8): return 7
                case (9, 0...4): return 1
                case (9, 5...8): return 2
                default: return nil
                }
            }
        },
        score: 1240,
        best: 4820,
        isGameOver: false
    )

    private static var reloadPending = false

    /// Coalesces the burst of saves a single move can cause into one redraw.
    private static func reloadWidget() {
        #if os(iOS) && canImport(WidgetKit)
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            reloadPending = false
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
        #endif
    }
}
