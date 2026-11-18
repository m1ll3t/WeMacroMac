import Foundation

public struct LensParameters: Equatable, Sendable {
    public var input: DepthInput
    public var aperture: Double
    public var cameraBrand: String
    public var cameraID: String
    public init(lens: MacroLens) {
        input = DepthInput()
        aperture = lens.apertures[0]
        cameraBrand = "索尼"
        cameraID = "索尼:A7R V"
        if lens == .manual { input.na = 0.1; input.magnification = 5 }
        if lens != .manual {
            input.magnification = lens.range.lowerBound
            if lens == .macro { input.magnification = 1 }
            input.na = lens.estimatedNA(aperture: aperture, magnification: input.magnification) ?? input.na
        }
    }
}
public struct TabMemory: Sendable {
    private var values: [MacroLens: LensParameters] = [:]
    public init() {}
    public mutating func exchange(from oldLens: MacroLens, parameters: LensParameters, to newLens: MacroLens) -> LensParameters {
        values[oldLens] = parameters
        return values[newLens] ?? LensParameters(lens: newLens)
    }
}
