// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 m1ll3t

import SwiftUI

/// Uses the same 20% black press feedback for every action button.
struct PressedOverlayStyle: ButtonStyle {
    var bordered = false
    var cornerRadius: CGFloat = 6
    var dimDisabled = true
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
    }
}
