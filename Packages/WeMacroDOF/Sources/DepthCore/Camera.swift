// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 m1ll3t

import Foundation

public struct CameraPreset: Identifiable, Hashable, Sendable {
    public let brand: String
    public let model: String
    public let pixelSize: Double
    public var id: String { brand + ":" + model }
}
public enum CameraCatalog {
    /// Transcribed from the user-supplied reference image; approximate grouped values, with explicit footnotes preserved.
    public static let all: [CameraPreset] = {
        var values: [CameraPreset] = []
        func add(_ brand: String, _ pixel: Double, _ models: [String]) {
            values += models.map { CameraPreset(brand: brand, model: $0, pixelSize: pixel) }
        }
        add("索尼", 3.76, ["A7R IV", "A7R V", "A7CR", "A6700"])
        add("索尼", 4.53, ["A7R II", "A7R III"])
        add("索尼", 4.88, ["A7R"])
        add("索尼", 5.12, ["A7 IV", "A7C II"])
        add("索尼", 6.00, ["A7", "A7 II", "A7 III", "A9", "A9 II", "A9 III", "A7C"])
        add("富士", 3.03, ["X-T5", "X-H2"])
        add("富士", 3.76, ["GFX100", "X-E4"])
        add("富士", 5.36, ["GFX50S"])
        add("哈苏", 3.76, ["X2D"]); add("哈苏", 5.36, ["X1D"])
        add("佳能", 3.20, ["EOS 90D", "EOS R7"])
        add("佳能", 3.72, ["EOS R10", "EOS R50", "EOS 850D"])
        add("佳能", 4.09, ["EOS 5DS"]); add("佳能", 4.09, ["EOS 7D Mark II"])
        add("佳能", 4.39, ["EOS R5"])
        add("佳能", 5.36, ["EOS R", "EOS 5D Mark IV"])
        add("佳能", 5.77, ["EOS RP", "EOS 6D Mark II"])
        add("佳能", 6.00, ["EOS R3", "EOS R8"])
        add("佳能", 6.41, ["EOS 5D Mark II", "EOS-1Ds Mark III"])
        add("佳能", 6.58, ["EOS-1D X Mark II", "EOS-1D X Mark III"])
        add("佳能", 6.94, ["EOS-1D X"]); add("佳能", 7.21, ["EOS-1Ds Mark II"])
        add("佳能", 8.20, ["EOS 5D"])
        add("尼康", 3.91, ["D5600"])
        add("尼康", 4.22, ["Z fc", "D7500", "D500"])
        add("尼康", 4.39, ["Z7", "Z8", "Z9", "D850"])
        add("尼康", 4.88, ["D800", "D810"])
        add("尼康", 6.00, ["Z5", "Z6", "Z f", "D780", "D3X"])
        add("尼康", 6.41, ["D5", "D6"]); add("尼康", 7.30, ["D4"]); add("尼康", 8.43, ["D3"])
        add("松下", 3.03, ["G9 II", "GH6"])
        add("松下", 3.33, ["G9", "GH5"]); add("松下", 3.76, ["GH4"])
        add("松下", 4.30, ["S1R"]); add("松下", 6.00, ["S1", "S5", "S9"])
        add("奥林巴斯 / OM SYSTEM", 3.33, ["OM-1", "OM-5", "E-M1 Mark II"])
        add("奥林巴斯 / OM SYSTEM", 3.76, ["E-M1"])
        add("徕卡", 3.76, ["M11"]); add("徕卡", 6.00, ["M10"])
        add("徕卡", 6.84, ["M8"]); add("徕卡", 6.80, ["M9"])
        add("适马", 3.76, ["fp L"])
        add("宾得", 3.76, ["K-3 III"]); add("宾得", 3.91, ["KP", "K-70", "K-3 II"])
        add("宾得", 4.88, ["K-1"]); add("宾得", 6.06, ["645D"])
        return values
    }()
    public static let brands = ["手动输入", "索尼", "佳能", "尼康", "富士", "松下", "奥林巴斯 / OM SYSTEM", "徕卡", "适马", "宾得", "哈苏"]
    public static func cameras(brand: String) -> [CameraPreset] { all.filter { $0.brand == brand }.sorted {
        $0.model.compare($1.model, options: [.caseInsensitive, .numeric], locale: Locale(identifier: "en_US_POSIX")) == .orderedAscending
    } }
}
