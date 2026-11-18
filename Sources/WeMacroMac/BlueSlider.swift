import SwiftUI
import AppKit

/// A native slider with a consistent selected-track and thumb color on macOS.
struct BlueSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.cell = BlueSliderCell()
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.isContinuous = true
        slider.setAccessibilityLabel("倍率")
        configure(slider)
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        configure(slider)
    }
    private func configure(_ slider: NSSlider) {
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.numberOfTickMarks = step.map { Int(((range.upperBound - range.lowerBound) / $0).rounded()) + 1 } ?? 0
        slider.allowsTickMarkValuesOnly = step != nil
        slider.doubleValue = value
    }
    final class Coordinator: NSObject {
        var parent: BlueSlider
        init(_ parent: BlueSlider) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) { parent.value = sender.doubleValue }
    }
}

final class BlueSliderCell: NSSliderCell {
    private let blue = NSColor(red: 0, green: 0.48, blue: 1, alpha: 1)
    private var horizontalRange: ClosedRange<CGFloat> {
        let bounds = controlView?.bounds ?? .zero
        return (bounds.minX + 10)...max(bounds.minX + 10, bounds.maxX - 10)
    }
    private func position(_ fraction: Double) -> CGFloat {
        let range = horizontalRange
        return range.lowerBound + CGFloat(min(1, max(0, fraction))) * (range.upperBound - range.lowerBound)
    }
    override func knobRect(flipped: Bool) -> NSRect {
        var rect = super.knobRect(flipped: flipped)
        let fraction = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0
        rect.origin.x = position(fraction) - rect.width / 2
        return rect
    }
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let range = horizontalRange
        let knob = knobRect(flipped: flipped)
        let track = NSRect(x: range.lowerBound, y: knob.midY - 2,
                           width: range.upperBound - range.lowerBound, height: 4)
        NSColor(white: 0.84, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        let selected = NSRect(x: track.minX, y: track.minY,
                              width: max(0, knob.midX - track.minX), height: track.height)
        blue.setFill()
        NSBezierPath(roundedRect: selected, xRadius: 2, yRadius: 2).fill()
    }
    override func drawTickMarks() {
        guard numberOfTickMarks > 1 else { return }
        let flipped = controlView?.isFlipped ?? false
        let centerY = knobRect(flipped: flipped).midY
        let y = flipped ? centerY + 9 : centerY - 13
        NSColor(white: 0.70, alpha: 1).setFill()
        for index in 0..<numberOfTickMarks {
            let x = position(Double(index) / Double(numberOfTickMarks - 1))
            NSRect(x: x - 0.5, y: y, width: 1, height: 4).fill()
        }
    }
    override func drawKnob(_ knobRect: NSRect) {
        let diameter: CGFloat = 16
        let thumb = NSRect(x: knobRect.midX - diameter / 2, y: knobRect.midY - diameter / 2,
                           width: diameter, height: diameter)
        blue.setFill()
        NSBezierPath(ovalIn: thumb).fill()
    }
}
