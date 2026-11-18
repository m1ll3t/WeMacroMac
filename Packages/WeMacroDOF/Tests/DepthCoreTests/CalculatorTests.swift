import Testing
import DepthCore
@Test func referenceTable() throws {
    let r = try DepthCalculator.calculate(.init())
    #expect(abs(r.depthMicrons - 8.512) < 0.00001)
    #expect(abs(r.sampling - 3.48) < 0.00001)
    #expect(abs(r.stepMicrons - 5.9584) < 0.00001)
    #expect(r.quantizedStepMicrons == 5.9375)
    let other = try DepthCalculator.calculate(.init(na: 0.5, magnification: 20))
    #expect(abs(other.depthMicrons - 2.128) < 0.00001)
    #expect(abs(other.sampling - 3.48) < 0.00001)
}
@Test func validationAndPixelScaling() throws {
    #expect(throws: DepthError.self) { try DepthCalculator.calculate(.init(na: 0)) }
    #expect(throws: DepthError.self) { try DepthCalculator.calculate(.init(overlap: 1)) }
    #expect(throws: DepthError.self) { try DepthCalculator.calculate(.init(pixelSize: .nan)) }
    let r = try DepthCalculator.calculate(.init(pixelSize: 7.52))
    #expect(abs(r.sampling - 1.74) < 0.00001)
    #expect(r.samplingState == "欠采样")
}
@Test func quantizationNeverExceedsRecommendedStep() throws {
    for na in [0.025, 0.1, 0.25, 0.5, 0.95] {
        let r = try DepthCalculator.calculate(.init(na: na))
        if let q = r.quantizedStepMicrons { #expect(q <= r.stepMicrons) }
    }
}
@Test func lensConversion() throws {
    #expect(MacroLens.aksen45.apertures == [2.8,4,5.6,8,11])
    #expect(MacroLens.aksen175.apertures == [1.7,2,2.8,4,5.6])
    let na = try #require(MacroLens.aksen45.estimatedNA(aperture: 2.8, magnification: 1))
    #expect(abs(na - 0.0892857143) < 0.000001)
    #expect(MacroLens.aksen45.tableNA(aperture: 2.8, magnification: 1) == 0.09)
    #expect(MacroLens.aksen175.tableNA(aperture: 1.7, magnification: 10) == 0.25)
    #expect(MacroLens.aksen175.tableNA(aperture: 2, magnification: 6) == 0.19)
    #expect(MacroLens.aksen175.tableNA(aperture: 2.8, magnification: 10) == 0.15)
    #expect(MacroLens.aksen175.estimatedNA(aperture: 8, magnification: 10) == nil)
    #expect(MacroLens.aksen45.estimatedNA(aperture: 2.8, magnification: 10) == nil)
}
@Test func aksenDepthUsesReferenceTableNA() throws {
    let result = try DepthCalculator.calculateForLens(.init(na: 0.2451, magnification: 5, pixelSize: 3.76, overlap: 0.2), lens: .aksen175, aperture: 1.7)
    #expect(abs(result.depthMicrons - (0.532 / (0.23 * 0.23))) < 0.000001)
    #expect(abs(result.sampling - (0.087 * 5 / 0.23)) < 0.000001)
}
@Test func recommendedApertureUsesSamplingBand() throws {
    #expect(MacroLens.aksen45.recommendedAperture(magnification: 3.5, pixelSize: 3.76) == 2.8)
    #expect(MacroLens.aksen45.recommendedAperture(magnification: 1, pixelSize: 3.76) == 8)
    #expect(MacroLens.aksen175.recommendedAperture(magnification: 10, pixelSize: 3.76) == 1.7)
    #expect(MacroLens.manual.recommendedAperture(magnification: 3, pixelSize: 3.76) == nil)
    #expect(MacroLens.aksen45.recommendedAperture(magnification: 8, pixelSize: 3.76) == nil)
    for lens in [MacroLens.aksen45, .aksen175] {
        for m in stride(from: lens.range.lowerBound, through: lens.range.upperBound, by: 0.5) {
            let f = try #require(lens.recommendedAperture(magnification: m, pixelSize: 3.76))
            #expect(lens.apertures.contains(f))
        }
    }
}
@Test func cameraPresetsMatchReference() {
    #expect(Set(CameraCatalog.all.map(\.id)).count == CameraCatalog.all.count)
    #expect(CameraCatalog.all.first { $0.id == "索尼:A7R V" }?.pixelSize == 3.76)
    #expect(CameraCatalog.all.first { $0.id == "佳能:EOS R50" }?.pixelSize == 3.72)
    #expect(CameraCatalog.all.first { $0.id == "尼康:D3" }?.pixelSize == 8.43)
    for brand in CameraCatalog.brands where brand != "手动输入" { #expect(!CameraCatalog.cameras(brand: brand).isEmpty) }
    #expect(CameraCatalog.all.allSatisfy { (3...9).contains($0.pixelSize) })
}
@Test func genericMacroLens() throws {
    #expect(MacroLens.allCases.map(\.rawValue) == ["微距镜头", "AKSNE 1-5x", "AKSEN 5-10x", "显微物镜"])
    #expect(MacroLens.macro.apertures == [2.8,4,5.6,8,11,16])
    let na = try #require(MacroLens.macro.estimatedNA(aperture: 4, magnification: 1))
    #expect(na == 0.0625)
    let r = try DepthCalculator.calculate(.init(na: na, magnification: 1))
    #expect(abs(r.depthMicrons - 136.192) < 0.00001)
    #expect(MacroLens.macro.recommendedAperture(magnification: 1, pixelSize: 3.76) == 8)
    #expect(MacroLens.macro.estimatedNA(aperture: 22, magnification: 1) == nil)
    #expect(MacroLens.macro.tableNA(aperture: 2.8, magnification: 1) == nil)
}
@Test func fineMacroTracksCameraPixels() throws {
    let input = DepthInput(na: 3 / (2 * 2.8 * 4), magnification: 3, pixelSize: 3.76, overlap: 0.2)
    let r = try DepthCalculator.calculateFineMacro(input, aperture: 2.8)
    #expect(abs(r.depthMicrons - 44.8) < 0.000001)
    #expect(abs(r.stepMicrons - 35.84) < 0.000001)
    var largerPixel = input; largerPixel.pixelSize = 6
    let other = try DepthCalculator.calculateFineMacro(largerPixel, aperture: 2.8)
    #expect(abs(other.depthMicrons / r.depthMicrons - 6 / 3.76) < 0.000001)
    #expect(other.sampling < r.sampling)
    #expect(throws: DepthError.self) { try DepthCalculator.calculateFineMacro(input, aperture: .nan) }
    let microscope = try DepthCalculator.calculate(.init())
    #expect(abs(microscope.depthMicrons - 8.512) < 0.000001)
}
@Test func onlyGenericMacroUsesFineGeometry() throws {
    let na = try #require(MacroLens.aksen175.estimatedNA(aperture: 1.7, magnification: 10))
    let input = DepthInput(na: na, magnification: 10, pixelSize: 3.76, overlap: 0.2)
    let manual = try DepthCalculator.calculateForLens(input, lens: .manual, aperture: 1.7)
    #expect(abs(manual.depthMicrons - 7.4414032) < 0.000001)
    let aksen175 = try DepthCalculator.calculateForLens(input, lens: .aksen175, aperture: 1.7)
    #expect(abs(aksen175.depthMicrons - 8.512) < 0.000001)
    let aksen45 = try DepthCalculator.calculateForLens(.init(na: 0.1, magnification: 5, overlap: 0.2), lens: .aksen45, aperture: 2.8)
    #expect(abs(aksen45.depthMicrons - 27.142857142857) < 0.000001)
    #expect(throws: DepthError.self) { try DepthCalculator.calculateForLens(input, lens: .aksen45, aperture: 1.7) }
    let fine = try DepthCalculator.calculateForLens(input, lens: .macro, aperture: 1.7)
    #expect(abs(fine.depthMicrons - 6.732) < 0.000001)
}
@Test func eachTabRetainsItsOwnParameters() {
    var memory = TabMemory()
    var manual = LensParameters(lens: .manual)
    manual.input.na = 0.2451; manual.input.magnification = 5
    manual.input.overlap = 0.2; manual.cameraBrand = "手动输入"; manual.cameraID = ""; manual.input.pixelSize = 4.5
    var aksen = memory.exchange(from: .manual, parameters: manual, to: .aksen175)
    #expect(aksen.input.magnification == 5)
    aksen.input.magnification = 9.5; aksen.aperture = 4; aksen.input.overlap = 0.5
    aksen.cameraBrand = "佳能"; aksen.cameraID = "佳能:EOS R5"; aksen.input.pixelSize = 4.39
    let restoredManual = memory.exchange(from: .aksen175, parameters: aksen, to: .manual)
    #expect(restoredManual == manual)
    let restoredAKSEN = memory.exchange(from: .manual, parameters: restoredManual, to: .aksen175)
    #expect(restoredAKSEN == aksen)
    let macro = memory.exchange(from: .aksen175, parameters: restoredAKSEN, to: .macro)
    #expect(macro.input.magnification == 1)
    #expect(macro.aperture == 2.8)
}

@Test func macroMatchesUserWeMacroAPSCBaseline() throws {
    let na = try #require(MacroLens.macro.estimatedNA(aperture: 2.8, magnification: 1))
    let result = try DepthCalculator.calculateForLens(.init(na: na, magnification: 1, pixelSize: 3.76, overlap: 0.2), lens: .macro, aperture: 2.8)
    #expect(abs(result.depthMicrons - 201.6) < 0.000001)
    #expect(abs(result.stepMicrons - 161.28) < 0.000001)
}
