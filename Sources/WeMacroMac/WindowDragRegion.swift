// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 m1ll3t

import SwiftUI
import AppKit

/// Native dragging behind the header's interactive controls.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        private var initialFocusConfigured = false
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !initialFocusConfigured, let window else { return }
            initialFocusConfigured = true
            // Keep startup focus on a neutral view instead of the first numeric field.
            window.initialFirstResponder = self
            window.makeFirstResponder(self)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                window.makeFirstResponder(self)
            }
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
