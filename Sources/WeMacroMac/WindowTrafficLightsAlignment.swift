import SwiftUI
import AppKit

/// Places the actual native window controls inside our fixed-height header.
struct WindowTrafficLightsAlignment: NSViewRepresentable {
    func makeNSView(context: Context) -> ControlsView { ControlsView() }
    func updateNSView(_ nsView: ControlsView, context: Context) { nsView.install() }
    final class ControlsView: NSView {
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        private var buttons: [NSButton] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.install() }
        }
        func install() {
            guard buttons.isEmpty, let window else { return }
            for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(type) else { continue }
                button.removeFromSuperview()
                addSubview(button)
                buttons.append(button)
            }
            needsLayout = true
        }
        override func layout() {
            super.layout()
            for (index, button) in buttons.enumerated() {
                button.setFrameOrigin(NSPoint(x: 22 + CGFloat(index) * 22, y: (bounds.height - button.frame.height) / 2))
            }
        }
    }
}
