import SwiftUI

/// The settings sheet behind the gear icon.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    /// Called once the player has confirmed they want to throw the board away.
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.backgroundTop, Theme.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                handle

                Text("Settings")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Theme.ink)

                VStack(spacing: 0) {
                    themeRow
                    divider
                    vibrationRow
                }
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.card)
                )

                resetButton

                Spacer(minLength: 0)

                Text(GameView.versionLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.inkSoft)
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .alert("Start a new game?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) { }
            Button("Yes", role: .destructive) {
                onReset()
                dismiss()
            }
        } message: {
            Text("This board and your score will be lost. Your power-ups are kept.")
        }
    }

    private var handle: some View {
        Capsule()
            .fill(Theme.inkSoft.opacity(0.4))
            .frame(width: 38, height: 5)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.chipBorder)
            .frame(height: 1)
            .padding(.leading, 54)
    }

    // MARK: - Rows

    private var themeRow: some View {
        HStack(spacing: 12) {
            icon("moon.fill", tint: Color(hex: 0xA6BDF7))

            VStack(alignment: .leading, spacing: 1) {
                Text("Dark mode")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
                Text(settings.isDark ? "Dark" : "Light")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.inkSoft)
            }

            Spacer()

            Toggle("", isOn: $settings.isDark)
                .labelsHidden()
                .tint(Color(hex: 0xA6BDF7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private var vibrationRow: some View {
        HStack(spacing: 12) {
            icon("iphone.radiowaves.left.and.right", tint: Color(hex: 0xA8E6B8))

            VStack(alignment: .leading, spacing: 1) {
                Text("Vibrations")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
                Text(settings.vibrations ? "On" : "Off")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.inkSoft)
            }

            Spacer()

            Toggle("", isOn: $settings.vibrations)
                .labelsHidden()
                .tint(Color(hex: 0x7FBF93))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func icon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.22))
            )
    }

    private var resetButton: some View {
        Button {
            confirmingReset = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .bold))
                Text("Reset game")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundColor(Color(hex: 0xE8555F))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.card)
            )
        }
        .buttonStyle(.plain)
    }
}
