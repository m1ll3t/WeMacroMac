// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 m1ll3t

import Foundation
struct RailError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
struct RailSettings: Codable, Equatable {
    var settling = 0.3
    var interval = 0.5
    var shutters = 1
    var backlash = 220.0
    var step = 1.0
    var microns = false
    var compensate = true
    var beep = true
    var returnToStart = false
    var travelLimit = 100.0
    var english = false
    var roundedStep: Double { microns ? floor(step) : floor(step * 10) / 10 }
    var stepPulses: Int { max(1, Int(ceil((microns ? (roundedStep == 1 ? 0.9375 : roundedStep) / 1000 : roundedStep) * 6400))) }
    func validate() throws {
        guard settling.isFinite, (0.01...99).contains(settling), interval.isFinite, (0.01...99).contains(interval) else { throw RailError("等待时间和间隔须在 0.01–99 秒之间") }
        guard (1...9).contains(shutters), backlash.isFinite, (0...1000).contains(backlash), step.isFinite, step > 0, step <= (microns ? 1000 : 100) else { throw RailError("请检查步长、每步快门数和回差") }
    }
}
enum RailProtocol {
    // Official Windows NewControler.beep uses command 0x12 with zero payload;
    // its write method adds the CRC using the same frame format below.
    static func crc(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xffff
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xa001 : crc >> 1 }
        }
        return crc
    }
    static func frame(_ command: UInt8, mode: UInt8 = 0, pulses: Int = 0) throws -> Data {
        guard (0...0xffffff).contains(pulses) else { throw RailError("运动脉冲数超出协议范围") }
        var b: [UInt8] = [0xa5, 0x5a, command, mode, 0, 0, 0, UInt8((pulses >> 16) & 255), UInt8((pulses >> 8) & 255), UInt8(pulses & 255)]
        let c = crc(b); b += [UInt8(c & 255), UInt8(c >> 8)]
        return Data(b)
    }
}
/// A conservative event recognizer. Full firmware response framing remains unverified.
struct ReplyParser {
    var buffer: [UInt8] = []
    mutating func feed(_ data: Data) -> [UInt8] {
        buffer += data
        var events: [UInt8] = []
        while buffer.count >= 3 {
            if buffer[0] == 0x5a && buffer[1] == 0xa5 {
                events.append(buffer[2]); buffer.removeFirst(3)
            } else { buffer.removeFirst() }
        }
        return events
    }
}
