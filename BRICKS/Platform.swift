import CoreGraphics
#if os(iOS)
import UIKit
#endif

/// The few ways the platforms differ in how the game is played. Views ask these questions
/// instead of checking the OS themselves, so the per-platform decisions live in one place.
enum Platform {

    /// How pieces get from the tray onto the board.
    enum Input {
        /// Drag with a finger, a pointer or a pinch: iPhone, iPad, Mac, Vision Pro.
        case drag
        /// Pick a piece, move it on the board, press to place: Apple TV's remote.
        case remote
        /// Pick a piece, tap the board to aim, tap again to place: Apple Watch.
        case tap
    }

    static let input: Input = {
        #if os(tvOS)
        return .remote
        #elseif os(watchOS)
        return .tap
        #else
        return .drag
        #endif
    }()

    /// Whether a dragged piece should float above the touch point. On a phone the finger
    /// covers what it's dragging. An iPad's cells are big enough to see past the finger,
    /// and a lift sized to them throws the piece far above it; a pointer or a Vision Pro
    /// pinch covers nothing. So everywhere else the piece stays right under the touch.
    static let liftsDraggedPiece: Bool = {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }()

    /// The kind of device, as the "Play on…" achievements name it.
    static let device: String = {
        #if os(macOS)
        return "mac"
        #elseif os(tvOS)
        return "tv"
        #elseif os(visionOS)
        return "vision"
        #elseif os(watchOS)
        return "watch"
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #else
        return "iphone"
        #endif
    }()

    /// Text and chrome scale. Apple TV is read from across the room.
    static let uiScale: CGFloat = {
        #if os(tvOS)
        return 1.6
        #else
        return 1
        #endif
    }()

    /// Sheets get a Done button where there is no swipe-to-dismiss.
    static let sheetsNeedDoneButton: Bool = {
        #if os(iOS)
        return false
        #else
        return true
        #endif
    }()

    /// Whether the player can choose light or dark. Apple Watch is always dark, so the
    /// setting would do nothing there.
    static let supportsAppearanceChoice: Bool = {
        #if os(watchOS)
        return false
        #else
        return true
        #endif
    }()
}
