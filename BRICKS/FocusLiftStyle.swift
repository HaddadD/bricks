import SwiftUI

/// Shows a button's content as drawn, without system chrome: lifted with a shadow while
/// it has focus (Apple TV's remote, a keyboard) and dipped while pressed. Used where the
/// default button look would fight the game's own art: tray pieces, the board, chips.
struct FocusLiftStyle: ButtonStyle {
    var focusedScale: CGFloat = 1.1

    func makeBody(configuration: Configuration) -> some View {
        Lifted(configuration: configuration, focusedScale: focusedScale)
    }

    private struct Lifted: View {
        let configuration: Configuration
        let focusedScale: CGFloat
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : (isFocused ? focusedScale : 1))
                .shadow(
                    color: Theme.shadow.opacity(isFocused ? 0.55 : 0),
                    radius: isFocused ? 14 : 0,
                    y: isFocused ? 8 : 0
                )
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
