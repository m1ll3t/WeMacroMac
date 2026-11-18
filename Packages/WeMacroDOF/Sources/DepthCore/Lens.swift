import Foundation
public enum MacroLens: String, CaseIterable, Sendable {
    case macro = "微距镜头"
    case aksen45 = "AKSNE 1-5x"
    case aksen175 = "AKSEN 5-10x"
    case manual = "显微物镜"
    public var apertures: [Double] {
        if self == .macro { return [2.8, 4, 5.6, 8, 11, 16] }
        return self == .aksen175 ? [1.7, 2, 2.8, 4, 5.6] : [2.8, 4, 5.6, 8, 11]
    }
    public var range: ClosedRange<Double> {
        if self == .macro { return 0.1...10 }
        return self == .aksen175 ? 5...10 : 1...5
    }
    public func estimatedNA(aperture: Double, magnification: Double) -> Double? {
        guard self != .manual, apertures.contains(aperture), magnification.isFinite, range.contains(magnification) else { return nil }
        return magnification / (2 * aperture * (1 + magnification))
    }
    public func tableNA(aperture: Double, magnification: Double) -> Double? {
        guard self == .aksen45 || self == .aksen175 else { return nil }
        guard estimatedNA(aperture: aperture, magnification: magnification) != nil,
              let row = apertures.firstIndex(of: aperture) else { return nil }
        let x: [Double] = self == .aksen175 ? [5, 6, 7, 8, 9, 10] : [1, 1.5, 2, 3, 4, 5]
        let rows: [[Double]] = self == .aksen175 ? [
            [0.23,0.23,0.24,0.24,0.24,0.25], [0.19,0.19,0.20,0.20,0.21,0.21],
            [0.14,0.14,0.14,0.14,0.15,0.15], [0.10,0.10,0.10,0.10,0.10,0.10], [0.07,0.07,0.07,0.07,0.07,0.07]
        ] : [
            [0.09,0.10,0.11,0.12,0.13,0.14], [0.06,0.07,0.08,0.09,0.09,0.10],
            [0.04,0.05,0.05,0.06,0.07,0.07], [0.03,0.04,0.04,0.04,0.05,0.05], [0.02,0.02,0.03,0.03,0.03,0.03]
        ]
        if magnification == x.last { return rows[row].last }
        for i in 0..<(x.count - 1) where magnification >= x[i] && magnification <= x[i+1] {
            let t = (magnification-x[i])/(x[i+1]-x[i])
            return rows[row][i] + t * (rows[row][i+1]-rows[row][i])
        }
        return nil
    }
}

extension MacroLens {
    /// Select from the lens's real stops using the reference sampling band, not a claim of optical optimum.
    public func recommendedAperture(magnification: Double, pixelSize: Double) -> Double? {
        guard self != .manual, magnification.isFinite, range.contains(magnification), pixelSize.isFinite, (0.1...100).contains(pixelSize) else { return nil }
        let candidates = apertures.compactMap { f -> (Double, Double, Double)? in
            let na: Double?
            switch self {
            case .aksen45, .aksen175:
                na = tableNA(aperture: f, magnification: magnification)
            case .macro:
                na = estimatedNA(aperture: f, magnification: magnification)
            case .manual:
                na = nil
            }
            guard let na else { return nil }
            let sampling = 0.087 * magnification / na * (3.76 / pixelSize)
            let outside = max(2.3 - sampling, sampling - 3.5, 0)
            return (f, outside, abs(sampling - 2.9))
        }
        return candidates.min { a, b in
            if abs(a.1 - b.1) > 1e-10 { return a.1 < b.1 }
            if abs(a.2 - b.2) > 1e-10 { return a.2 < b.2 }
            return a.0 < b.0
        }?.0
    }
}
