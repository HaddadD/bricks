import SwiftUI
import WidgetKit

/// The BRICKS! widget: the game in progress and its score. Small and medium sizes; the
/// small one also shows in CarPlay and StandBy. It only displays (no playing in a widget),
/// and it's blank with a note when the player has switched it off in the app's Settings.
@main
struct BRICKSWidgets: WidgetBundle {
    var body: some Widget {
        BoardWidget()
    }
}

struct BoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: BoardProvider()) { entry in
            BoardWidgetView(entry: entry)
        }
        .configurationDisplayName("BRICKS!")
        .description("Your game in progress and your score.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BoardEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let enabled: Bool
}

/// The app redraws the widget whenever the game changes, so a timeline is a single entry
/// that never expires on its own.
struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: .now, snapshot: .sample, enabled: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        // The widget gallery shows a sample game rather than the player's own.
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> BoardEntry {
        BoardEntry(date: .now, snapshot: WidgetSnapshot.load(), enabled: WidgetSnapshot.isEnabled)
    }
}

struct BoardWidgetView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetFace(snapshot: entry.snapshot, enabled: entry.enabled, wide: family == .systemMedium)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            }
    }
}
