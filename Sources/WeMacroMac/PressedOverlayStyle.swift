import SwiftUI

private struct RailButtonActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
extension EnvironmentValues {
    var railButtonAction: () -> Void {
        get { self[RailButtonActionKey.self] }
        set { self[RailButtonActionKey.self] = newValue }
    }
}

/// Uses the same 20% black press feedback for every action button.
struct PressedOverlayStyle: ButtonStyle {
    var bordered = false
    var cornerRadius: CGFloat = 6
    var dimDisabled = true
    var resetsCompletion = true
    @Environment(\.railButtonAction) private var buttonAction
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, bordered ? 10 : 0)
            .padding(.vertical, bordered ? 5 : 0)
            .background {
                if bordered {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(.white)
                }
            }
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(configuration.isPressed && isEnabled ? 0.20 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.black.opacity(0.18), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .opacity(isEnabled || !dimDisabled ? 1 : 0.45)
            .onChange(of:configuration.isPressed) { _, pressed in
                if !pressed && isEnabled && resetsCompletion {
                    DispatchQueue.main.async { buttonAction() }
                }
            }
    }
}
