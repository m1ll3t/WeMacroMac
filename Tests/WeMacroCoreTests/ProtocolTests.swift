// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 m1ll3t

import Testing
import Foundation
@testable import WeMacroMac

@Test func knownCRCVector() { #expect(RailProtocol.crc(Array("123456789".utf8)) == 0x4b37) }
@Test func movementFrame() throws {
    let b = Array(try RailProtocol.frame(0x40, pulses: 6400))
    #expect(b.count == 12)
    #expect(Array(b[0...2]) == [0xa5, 0x5a, 0x40])
    #expect(Array(b[3...6]) == [0, 0, 0, 0]) // no automatic shutter
    #expect(Array(b[7...9]) == [0, 0x19, 0])
    let crc = RailProtocol.crc(Array(b.prefix(10)))
    #expect(b[10] == UInt8(crc & 255)); #expect(b[11] == UInt8(crc >> 8))
    #expect(throws: RailError.self) { try RailProtocol.frame(0x40, pulses: 0x1000000) }
    #expect(throws: RailError.self) { try RailProtocol.frame(0x40, pulses: -1) }
}
@Test func fragmentAndNoiseHandling() {
    var p = ReplyParser()
    #expect(p.feed(Data([0xff, 0x5a])).isEmpty)
    #expect(p.feed(Data([0xa5])).isEmpty)
    #expect(p.feed(Data([0xf5, 0x5a, 0xa5, 0xf6])) == [0xf5, 0xf6])
    #expect(p.feed(Data([0xf5, 0xf6])).isEmpty)
}
@Test func decimalTimingAndQuantization() throws {
    var s = RailSettings(); s.microns = true; s.settling = 0.1; s.interval = 0.2
    try s.validate(); s.step = 1
    #expect(s.stepPulses == 6)
    let recovered = try JSONDecoder().decode(RailSettings.self, from: JSONEncoder().encode(s))
    #expect(recovered == s)
    s.interval = .nan
    #expect(throws: RailError.self) { try s.validate() }
}
@Test @MainActor func simulatedCaptureAndStop() async throws {
    let m = RailModel(scanAtStartup:false,persistSettings:false)
    m.kind = "模拟"; m.scan(); m.toggleConnection()
    m.settings.settling = 0.01; m.settings.interval = 0.01
    m.settings.microns = true; m.settings.compensate = false; m.settings.beep = false
    m.start = 0; m.end = 128; m.settings.step = 10
    m.run()
    for _ in 0..<200 {
        if !m.busy { break }; try await Task.sleep(for: .milliseconds(10))
    }
    #expect(m.error == nil); #expect(!m.busy); #expect(m.completed == 3); #expect(m.position == 0)
    #expect(m.log.filter { $0.contains("TX A5 5A 80") }.count == 1)
    #expect(m.log.filter { $0.contains("RX 5A A5 F5") }.count == 3)
    #expect(m.log.filter { $0.contains("TX A5 5A 41") }.count == 2)
    m.run(); try await Task.sleep(for: .milliseconds(10)); m.stop()
    try await Task.sleep(for: .milliseconds(100))
    #expect(!m.busy); #expect(m.start == nil); #expect(m.end == nil)
    // Endpoints can be set in either order after stopping, without a zero action.
    m.markEnd(); #expect(m.end == 0)
    m.position = -64; m.markStart(); #expect(m.start == 0); #expect(m.position == 0); #expect(m.end == 64)
    m.link.disconnect()
    m.markStart(); #expect(m.start == nil)
}

@Test @MainActor func tenTimesJogUsesTenFullSteps() async throws {
    let m = RailModel(scanAtStartup:false,persistSettings:false)
    m.kind = "模拟"; m.scan(); m.toggleConnection()
    m.settings.microns = false; m.settings.step = 1; m.settings.travelLimit = 100
    m.jog(1, large: true)
    for _ in 0..<150 {
        if !m.busy { break }; try await Task.sleep(for: .milliseconds(10))
    }
    #expect(m.error == nil); #expect(m.position == 64000)
    #expect(m.log.contains { $0.contains("TX A5 5A 40 00 00 00 00 00 FA 00") })
    m.jog(-1, large: true)
    for _ in 0..<150 {
        if !m.busy { break }; try await Task.sleep(for: .milliseconds(10))
    }
    #expect(m.error == nil); #expect(m.position == 0)
    m.link.disconnect()
}

@Test @MainActor func releasingHoldStopsNewSegments() async throws {
    let m = RailModel(scanAtStartup:false,persistSettings:false); m.kind = "模拟"; m.scan(); m.toggleConnection()
    m.settings.microns = true; m.settings.step = 500
    m.beginHold(1)
    try await Task.sleep(for: .milliseconds(320))
    m.endHold()
    for _ in 0..<100 { if !m.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
    #expect(!m.busy); #expect(!m.holding); #expect(m.error == nil)
    #expect(m.position > 0); #expect(m.positionEstimated)
    #expect(m.log.filter { $0.contains("TX A5 5A 40") }.count == 1)
    #expect(m.log.contains { $0.contains("TX A5 5A 20") })
    let p = m.position
    try await Task.sleep(for: .milliseconds(200)); #expect(m.position == p)
    m.link.disconnect()
}

@Test @MainActor func rangeRequiresBothEndpoints() {
    let m = RailModel(scanAtStartup:false,persistSettings:false)
    #expect(!m.hasRange); #expect(m.distance == 0)
    m.start = 6400; #expect(!m.hasRange); #expect(m.distance == 0)
    m.end = 16000; #expect(m.hasRange); #expect(m.distance == 1.5)
    m.start = 19200; #expect(m.distance == 0.5)
}

@Test @MainActor func startRebasesAndEndMeasuresFromZero() {
    let m = RailModel(scanAtStartup:false,persistSettings:false); m.kind = "模拟"; m.scan(); m.toggleConnection()
    m.position = -38400; m.end = -57600; m.markStart()
    #expect(m.start == 0); #expect(m.position == 0); #expect(m.end == -19200)
    m.position = -19200; m.markEnd()
    #expect(m.end == -19200); #expect(m.distance == 3)
    m.markStart(); #expect(m.start == 0); #expect(m.end == 0)
    m.link.disconnect()
}

@Test @MainActor func captureDirectionCanBeSwitched() async throws {
    for reverse in [true, false] {
        let m = RailModel(scanAtStartup:false,persistSettings:false)
        m.kind = "模拟"; m.scan(); m.toggleConnection()
        m.settings.settling = 0.01; m.settings.interval = 0.01
        m.settings.microns = true; m.settings.step = 10
        m.settings.compensate = false; m.settings.beep = false; m.settings.returnToStart = false
        m.start = 0; m.end = 128; m.captureEndToStart = reverse
        m.run()
        for _ in 0..<300 { if !m.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(m.error == nil)
        #expect(!m.busy)
        #expect(m.completed == 3)
        #expect(m.position == (reverse ? 0 : 128))
        m.link.disconnect()
    }
}

@Test @MainActor func completedCaptureCountsEveryShutterAndResetsOnMovement() async throws {
    let m = RailModel(scanAtStartup:false,persistSettings:false)
    m.kind = "模拟"; m.scan(); m.toggleConnection()
    m.settings.settling = 0.01; m.settings.interval = 0.01
    m.settings.microns = true; m.settings.step = 10; m.settings.shutters = 3
    m.settings.compensate = false; m.settings.returnToStart = false; m.settings.beep = true
    m.start = 0; m.end = 128
    #expect(m.remainingShots == 9)
    m.run()
    for _ in 0..<400 {
        #expect(m.remainingShots + m.shotsTaken == 9)
        if !m.busy { break }
        try await Task.sleep(for:.milliseconds(10))
    }
    #expect(!m.busy); #expect(m.error == nil); #expect(m.captureFinished)
    #expect(m.shotsTaken == 9); #expect(m.remainingShots == 0)
    #expect(m.log.filter { $0.contains("TX A5 5A 04") }.count == 9)
    #expect(m.log.filter { $0.contains("TX A5 5A 12 00 00 00 00 00 00 00") }.count == 1)
    m.jog(1)
    #expect(!m.captureFinished); #expect(m.shotsTaken == 0); #expect(m.completed == 0)
    #expect(m.start == nil); #expect(m.end == nil); #expect(!m.hasRange)
    for _ in 0..<200 { if !m.busy { break }; try await Task.sleep(for:.milliseconds(10)) }
    #expect(m.error == nil)
    m.link.disconnect()
}

@Test @MainActor func rebasingPreservesEndpointDestination() async throws {
    let m = RailModel(scanAtStartup:false,persistSettings:false)
    m.kind = "模拟"; m.scan(); m.toggleConnection()
    m.settings.microns = false; m.settings.step = 1
    m.position = 64000; m.markEnd()
    #expect(m.start == nil); #expect(m.end == 64000); #expect(!m.hasRange)
    m.position = 25600; m.markStart()
    #expect(m.start == 0); #expect(m.end == 38400); #expect(m.distance == 6)
    m.go(m.end)
    for _ in 0..<200 { if !m.busy { break }; try await Task.sleep(for:.milliseconds(10)) }
    #expect(m.position == 38400); #expect(m.error == nil)
    m.link.disconnect()
}

@Test @MainActor func arrowTapFinishesExactlyOneStep() async throws {
    let m = RailModel(scanAtStartup:false,persistSettings:false)
    m.kind = "模拟"; m.scan(); m.toggleConnection()
    m.settings.microns = true; m.settings.step = 500
    m.beginStepHold(-1)
    m.endStepHold()
    for _ in 0..<200 { if !m.busy { break }; try await Task.sleep(for:.milliseconds(10)) }
    #expect(m.error == nil); #expect(!m.busy); #expect(!m.steppingHeld)
    #expect(m.position == -3200)
    #expect(m.log.filter { $0.contains("TX A5 5A 41") }.count == 1)
    m.link.disconnect()
}

@Test @MainActor func arrowHoldRepeatsCurrentStepAndSpeedWithoutQueuing() async throws {
    for microns in [false,true] {
        let m = RailModel(scanAtStartup:false,persistSettings:false)
        m.kind = "模拟"; m.scan(); m.toggleConnection()
        m.settings.microns = microns; m.settings.step = microns ? 10:0.5
        let step = m.settings.stepPulses
        m.beginStepHold(1)
        try await Task.sleep(for:.milliseconds(850))
        m.endStepHold()
        for _ in 0..<200 { if !m.busy { break }; try await Task.sleep(for:.milliseconds(10)) }
        let commands = m.log.filter { $0.contains("TX A5 5A 40") }.count
        #expect(commands >= 2); #expect(m.position == commands * step)
        #expect(m.error == nil); #expect(!m.steppingHeld); #expect(!m.positionEstimated)
        #expect(m.log.contains { $0.contains(microns ? "TX A5 5A 80 00":"TX A5 5A 80 FF") })
        let previousPosition = m.position
        try await Task.sleep(for:.milliseconds(200))
        #expect(m.position == previousPosition)
        m.link.disconnect()
    }
}

@Test @MainActor func calculatorRemainsIndependentWhileCaptureIsRunning() async throws {
    let m = RailModel(scanAtStartup:false,persistSettings:false)
    m.kind = "模拟"; m.scan(); m.toggleConnection()
    m.settings.microns = true; m.settings.step = 10
    m.settings.settling = 0.01; m.settings.interval = 0.03
    m.settings.shutters = 2; m.settings.compensate = false
    m.settings.beep = false; m.settings.returnToStart = false
    m.start = 0; m.end = 128
    m.run()
    try await Task.sleep(for:.milliseconds(30))
    #expect(m.busy); #expect(m.capturing)
    m.controlsBlocked = true // Calculator overlay blocks rail keyboard controls only.
    let calculator = CalculatorModel()
    calculator.lens = .aksen175
    calculator.input.magnification = 7.5; calculator.aperture = 2.8
    calculator.updateNA()
    #expect(calculator.input.na > 0)
    m.beginStepHold(1) // Arrow control must not interfere with the active capture.
    #expect(!m.steppingHeld); #expect(m.settings.step == 10)
    for _ in 0..<300 { if !m.busy { break }; try await Task.sleep(for:.milliseconds(10)) }
    #expect(m.error == nil); #expect(m.captureFinished)
    #expect(m.shotsTaken == 6); #expect(m.remainingShots == 0)
    m.link.disconnect()
}

@Test @MainActor func singleEndpointEnablesRunOnlyAfterChangingPosition() {
    let m = RailModel(scanAtStartup:false,persistSettings:false)
    m.kind = "模拟"; m.scan(); m.toggleConnection()
    #expect(!m.canRun)
    m.position = 6400; m.markStart()
    #expect(!m.canRun)
    let count = m.log.count
    m.run()
    #expect(!m.busy); #expect(m.end == nil); #expect(m.log.count == count)
    m.position = 64; #expect(m.canRun)
    m.position = 0; #expect(!m.canRun)
    m.clearCaptureData(); m.position = 6400; m.markEnd()
    #expect(!m.canRun)
    m.run(); #expect(!m.busy); #expect(m.start == nil)
    m.position = 6464; #expect(m.canRun)
    m.position = 6400; #expect(!m.canRun)
    m.link.disconnect()
}

@Test @MainActor func runCompletesMissingEndpointInBothOrdersAndDirections() async throws {
    for endFirst in [false,true] {
        for reverse in [false,true] {
            let m = RailModel(scanAtStartup:false,persistSettings:false)
            m.kind = "模拟"; m.scan(); m.toggleConnection()
            m.settings.microns = true; m.settings.step = 10; m.settings.shutters = 1
            m.settings.settling = 0.01; m.settings.interval = 0.01
            m.settings.compensate = false; m.settings.returnToStart = false; m.settings.beep = false
            m.captureEndToStart = reverse
            if endFirst {
                m.position = 50000; m.markEnd(); m.position = 49872
            } else {
                m.position = 50000; m.markStart(); m.position = 128
            }
            #expect(m.canRun); #expect(!m.hasRange)
            m.run()
            #expect(m.start == 0); #expect(m.end == 128); #expect(m.busy)
            for _ in 0..<300 { if !m.busy { break }; try await Task.sleep(for:.milliseconds(10)) }
            #expect(m.error == nil); #expect(m.captureFinished)
            #expect(m.position == (reverse ? 0:128))
            #expect(m.shotsTaken == 3); #expect(m.remainingShots == 0)
            m.link.disconnect()
        }
    }
}

@Test @MainActor func controlsWhileBusyAreDiscardedWithoutCommandsOrEndpointChanges() async throws {
    let m = RailModel(scanAtStartup:false,persistSettings:false)
    m.kind = "模拟"; m.scan(); m.toggleConnection()
    m.settings.microns = true; m.settings.step = 10
    m.markStart(); m.jog(1)
    #expect(m.busy)
    for _ in 0..<20 {
        m.jog(-1,large:true); m.go(10000)
        m.markStart(); m.markEnd(); m.run(); m.shutter(); m.calibrate()
        m.beginStepHold(-1); m.beginHold(-1)
    }
    #expect(m.start == 0); #expect(m.end == nil)
    for _ in 0..<200 { if !m.busy { break }; try await Task.sleep(for:.milliseconds(10)) }
    #expect(m.error == nil); #expect(m.position == 64)
    #expect(m.log.filter { $0.contains("TX A5 5A 40") }.count == 1)
    #expect(!m.log.contains { $0.contains("TX A5 5A 41") || $0.contains("TX A5 5A 04") || $0.contains("TX A5 5A 12") })
    let sent = m.log.filter { $0.contains("TX ") }.count
    try await Task.sleep(for:.milliseconds(250))
    #expect(m.log.filter { $0.contains("TX ") }.count == sent)
    #expect(m.start == 0); #expect(m.end == nil); #expect(m.canRun)
    m.link.disconnect()
}
