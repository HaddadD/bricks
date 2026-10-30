import SwiftUI
import StoreKit

/// Copies downloaded from the App Store must be the latest version: when the store has a
/// newer one, `UpdateRequiredView` covers the game until the player updates. TestFlight,
/// Xcode and DEBUG builds never check. Anything that goes wrong (offline, a failed lookup)
/// lets the player in, so a store hiccup can't lock anyone out.
@MainActor
final class UpdateCheck: ObservableObject {
    /// The App Store's version, once the installed one is found to be behind it.
    @Published private(set) var requiredVersion: String?
    private var lastCheck: Date?

    static let appID = "6828698183"
    /// The lookup shows a new version before every storefront can download it, and an
    /// update the player can't get yet would lock them out. A day after release it's out
    /// everywhere.
    private static let grace: TimeInterval = 24 * 60 * 60

    /// Runs on launch and whenever the app comes back to the foreground, at most hourly.
    func check() async {
        #if DEBUG
        // `-updateRequired` shows the screen without a store lookup.
        if ProcessInfo.processInfo.arguments.contains("-updateRequired") { requiredVersion = "9.9" }
        #else
        guard requiredVersion == nil else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 60 * 60 { return }
        lastCheck = Date()

        guard await Self.isFromAppStore(),
              let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let store = await Self.storeVersion(),
              Date().timeIntervalSince(store.released) > Self.grace,
              AppVersion.isOlder(installed, than: store.version)
        else { return }
        requiredVersion = store.version
        #endif
    }

    /// Only an App Store download is production; TestFlight is sandbox, Xcode is xcode.
    private static func isFromAppStore() async -> Bool {
        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result
        else { return false }
        return transaction.environment == .production
    }

    private struct Lookup: Decodable {
        struct Entry: Decodable {
            let version: String
            let currentVersionReleaseDate: String?
        }
        let results: [Entry]
    }

    /// The live App Store version and when it was released, from the public lookup API.
    private static func storeVersion() async -> (version: String, released: Date)? {
        var url = URLComponents(string: "https://itunes.apple.com/lookup")!
        url.queryItems = [URLQueryItem(name: "id", value: appID)]
        if let region = Locale.current.region?.identifier {
            url.queryItems?.append(URLQueryItem(name: "country", value: region))
        }
        var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let entry = (try? JSONDecoder().decode(Lookup.self, from: data))?.results.first,
              let released = entry.currentVersionReleaseDate.flatMap(ISO8601DateFormatter().date(from:))
        else { return nil }
        return (entry.version, released)
    }
}

/// Covers the game when the App Store has a newer version, with a button to it where the
/// platform can open the store from an app.
struct UpdateRequiredView: View {
    let version: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Text("BRICKS!")
                .font(.system(size: 34 * Platform.uiScale, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex: 0xF08FB4), Color(hex: 0xA6BDF7)], startPoint: .leading, endPoint: .trailing)
                )
            Text("Version \(version) is out")
                .font(.system(size: 20 * Platform.uiScale, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.ink)
            Text(Self.storeURL == nil
                 ? "Update BRICKS! from the App Store to keep playing."
                 : "Update to keep playing. Your game and best score are saved.")
                .font(.system(size: 15 * Platform.uiScale, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.inkSoft)
                .multilineTextAlignment(.center)

            if let url = Self.storeURL {
                Button {
                    openURL(url)
                } label: {
                    Text("Update")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LinearGradient(colors: [Color(hex: 0xF08FB4), Color(hex: 0xB39BF0)], startPoint: .leading, endPoint: .trailing))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    /// The app's App Store page. Apple TV and Apple Watch can't open the store from an
    /// app, so there the screen just says where to go.
    private static let storeURL: URL? = {
        #if os(macOS)
        return URL(string: "macappstore://apps.apple.com/app/id\(UpdateCheck.appID)")
        #elseif os(iOS) || os(visionOS)
        return URL(string: "itms-apps://apps.apple.com/app/id\(UpdateCheck.appID)")
        #else
        return nil
        #endif
    }()
}
