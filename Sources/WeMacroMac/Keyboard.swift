import AppKit

/// Local to this application; no global keyboard or Accessibility permission.
@MainActor final class RailKeyboard {
    weak var model: RailModel?
    private var monitor: Any?
    private var pressed: Set<UInt16> = []
    private var heldKey: UInt16?
    func install(model: RailModel) {
        guard monitor == nil else { return }
        self.model = model
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handle(event)
            }
        }
    }
    func release() { pressed.removeAll(); heldKey = nil; model?.endStepHold(); model?.endHold() }
    private func endEditingOutsideField(_ event: NSEvent) {
        guard NSApp.modalWindow == nil,
              let window = event.window,
              let editor = window.firstResponder as? NSTextView,
              editor.isEditable,
              let content = window.contentView else { return }
        let editorPoint = editor.convert(event.locationInWindow, from: nil)
        if editor.bounds.contains(editorPoint) { return }
        let contentPoint = content.convert(event.locationInWindow, from: nil)
        var hit = content.hitTest(contentPoint)
        while let view = hit {
            // Switching to another field should retain normal text-editing behavior.
            if let field = view as? NSTextField, field.isEditable { return }
            hit = view.superview
        }
        // Commits valid input without consuming the click destined for another control.
        window.makeFirstResponder(nil)
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseDown {
            endEditingOutsideField(event)
            return event
        }
        guard [36, 51, 76, 114, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(Int(event.keyCode)), let model else { return event }
        if event.type == .keyUp {
            guard pressed.remove(event.keyCode) != nil else { return event }
            if heldKey == event.keyCode {
                heldKey = nil
                if event.keyCode == 125 || event.keyCode == 126 { model.endStepHold() }
                else { model.endHold() }
            }
            return nil
        }
        guard NSApp.isActive, NSApp.modalWindow == nil, !model.controlsBlocked else { return event }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let isEndpointKey = event.keyCode == 115 || event.keyCode == 119
        guard isReturn ? modifiers == [.command] : (isEndpointKey ? (modifiers.isEmpty || modifiers == [.shift]) : modifiers.isEmpty) else { return event }
        // Arrow keys keep their editing behavior while a parameter field is being edited.
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable { return event }
        let requiresConnection = ![51, 114, 117].contains(Int(event.keyCode))
        guard !requiresConnection || model.link.connected else { return event }
        if event.isARepeat || pressed.contains(event.keyCode) { return nil }
        pressed.insert(event.keyCode)
        switch event.keyCode {
        case 114: // Insert (Help on some Mac keyboards): open calculator, including during capture
            guard !model.busy || model.capturing else { return nil }
            model.calculatorRequest += 1
        case 115: // Home: mark start; Shift+Home: go to start
            guard !model.busy else { return nil }
            if modifiers == [.shift] {
                if let start = model.start { model.go(start) }
            } else { model.markStart() }
        case 119: // End: mark end; Shift+End: go to end
            guard !model.busy else { return nil }
            if modifiers == [.shift] {
                if let end = model.end { model.go(end) }
            } else { model.markEnd() }
        case 51, 117: // Backspace/Delete: clear recorded capture data without moving the rail
            model.clearCaptureData()
        case 36, 76: // Return and numeric keypad Enter
            guard !model.busy, model.canRun else { return nil }
            model.run()
        case 125, 126: // tap: one step; hold: repeat using the current step and speed
            guard !model.busy else { return nil }
            heldKey = event.keyCode
            model.beginStepHold(event.keyCode == 126 ? -1 : 1)
        case 116, 121: // Page Up: backward ten steps; Page Down: forward ten steps
            guard !model.busy else { return nil }
            model.jog(event.keyCode == 116 ? -1 : 1, large:true)
        case 123: // left: continuous backward
            guard !model.busy else { return nil }
            heldKey = event.keyCode; model.beginHold(-1)
        case 124: // right: continuous forward
            guard !model.busy else { return nil }
            heldKey = event.keyCode; model.beginHold(1)
        default: break
        }
        return nil
    }
}
