// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 m1ll3t

import Foundation

public struct DepthInput: Equatable, Sendable {
    public var na: Double
    public var magnification: Double
    public var pixelSize: Double
    public var overlap: Double
    public init(na: Double = 0.25, magnification: Double = 10, pixelSize: Double = 3.76, overlap: Double = 0.30) {
        self.na = na; self.magnification = magnification; self.pixelSize = pixelSize; self.overlap = overlap
    }
}
public struct DepthResult: Sendable {
    public let depthMicrons: Double
    public let stepMicrons: Double
    public let sampling: Double
    public let magnificationRange: ClosedRange<Double>
    public let quantizedStepMicrons: Double?
    public var samplingState: String { sampling < 2.3 ? "欠采样" : sampling <= 3.5 ? "合理采样" : "过采样" }
}
public enum DepthError: Error, LocalizedError {
    case invalid
    public var errorDescription: String? { "请输入有效参数：NA 0.0001–0.99、倍率 0.1–1000、像元 0.1–100 µm、重叠率 0–95%。" }
}
public enum DepthCalculator {
    /// Coefficients inferred from the user's rounded reference table, not a universal optical model.
    public static func calculate(_ input: DepthInput) throws -> DepthResult {
        guard input.na.isFinite, (0.0001...0.99).contains(input.na), input.magnification.isFinite, (0.1...1000).contains(input.magnification), input.pixelSize.isFinite, (0.1...100).contains(input.pixelSize), input.overlap.isFinite, (0...0.95).contains(input.overlap) else { throw DepthError.invalid }
        let depth = 0.532 / (input.na * input.na)
        let step = depth * (1 - input.overlap)
        let samplingFactor = 0.087 * (3.76 / input.pixelSize) / input.na
        let quantum = 0.3125
        let quantized = floor(step / quantum) * quantum
        return DepthResult(depthMicrons: depth, stepMicrons: step, sampling: input.magnification * samplingFactor, magnificationRange: (2.3 / samplingFactor)...(3.5 / samplingFactor), quantizedStepMicrons: quantized >= quantum ? quantized : nil)
    }
}

extension DepthCalculator {
    /// WeMacro macro DOF geometry calibrated to c=18 µm at pixel pitch 3.76 µm.
    /// This tolerance is not a bound on total diffraction + aberration + defocus blur.
    public static func calculateFineMacro(_ input: DepthInput, aperture: Double) throws -> DepthResult {
        guard aperture.isFinite, aperture > 0, aperture <= 64 else { throw DepthError.invalid }
        let base = try calculate(input)
        let cMicrons = 18 * input.pixelSize / 3.76
        let depth = 2 * cMicrons * aperture * (1 + input.magnification) / (input.magnification * input.magnification)
        let step = depth * (1 - input.overlap)
        let q = floor(step / 0.3125) * 0.3125
        return DepthResult(depthMicrons: depth, stepMicrons: step, sampling: base.sampling, magnificationRange: base.magnificationRange, quantizedStepMicrons: q >= 0.3125 ? q : nil)
    }
}

extension DepthCalculator {
    public static func calculateForLens(_ input: DepthInput, lens: MacroLens, aperture: Double) throws -> DepthResult {
        if lens == .macro { return try calculateFineMacro(input, aperture: aperture) }
        if lens == .aksen45 || lens == .aksen175 {
            guard let na = lens.tableNA(aperture: aperture, magnification: input.magnification) else { throw DepthError.invalid }
            var tableInput = input
            tableInput.na = na
            return try calculate(tableInput)
        }
        return try calculate(input)
    }
}
