import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class RailModel: ObservableObject {
    let link = RailTransport()
    private let persistSettings: Bool
    @Published var settings = RailSettings()
    @Published var controlsBlocked = false
    @Published var calculatorRequest = 0
    @Published var autoConnectEnabled = UserDefaults.standard.object(forKey: "autoConnectEnabled") as? Bool ?? UserDefaults.standard.object(forKey: "autoConnectBluetooth") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoConnectEnabled, forKey: "autoConnectEnabled")
            if autoConnectEnabled && !oldValue && !link.connected && !busy { scanAtLaunch() }
        }
    }
    @Published var kind = "蓝牙"
    @Published var selected = ""
    @Published var position = 0
    @Published var start: Int?
    @Published var end: Int?
    @Published var busy = false
    @Published var captureFinished = false
    @Published var shotsTaken = 0
    @Published var completed = 0
    @Published var capturing = false
    @Published var phase = "就绪"
    @Published var error: String?
    @Published var log: [String] = []
    @Published var paused = false
    @Published var steppingHeld = false
    @Published var holding = false
    @Published var captureEndToStart = true
    @Published var positionEstimated = false
    private var holdStarted: TimeInterval?
    private var holdStopRequested = false
    private var parser = ReplyParser()
    private var configuredPacket: Data?
    private var autoConnectionAttempted = false
    private var operation: Task<Void, Never>?
    private var token = UUID()
    private var completion: CheckedContinuation<Void, Error>?
    private var moveTimeout: Task<Void, Never>?
    private var connectionObserver: Any?
    private var sleepAssertion: NSObjectProtocol?
    var tr: Bool { settings.english }
    func text(_ zh: String, _ en: String) -> String { tr ? en : zh }
    var hasRange: Bool { start != nil && end != nil }
    var canRun: Bool {
        guard link.connected, !captureFinished else { return false }
        if let start, let end { return start != end }
        if let start { return position != start }
        if let end { return position != end }
        return false
    }
    var distance: Double { guard let start, let end else { return 0 }; return Double(abs(end - start)) / 6400 }
    var frames: Int {
        guard let start, let end, settings.step.isFinite, settings.step > 0, settings.step <= 1000 else { return 0 }
        return Int(ceil(Double(abs(end - start)) / Double(settings.stepPulses))) + 1
    }
    var remainingShots: Int { max(0, frames * settings.shutters - shotsTaken) }
    init(scanAtStartup: Bool = true, persistSettings: Bool = true) {
        self.persistSettings = persistSettings
        if let data = UserDefaults.standard.data(forKey: "settings.v01"), let s = try? JSONDecoder().decode(RailSettings.self, from: data), (try? s.validate()) != nil { settings = s }
        if !UserDefaults.standard.bool(forKey: "defaults.mm.v02") {
            settings.step = 1; settings.microns = false
            UserDefaults.standard.set(true, forKey: "defaults.mm.v02")
            saveDefaults()
        }
        link.onDevice = { [weak self] device in
            guard let self, self.kind == "蓝牙" else { return }
            let name = device.name.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
            guard name.contains("hc08") || name.contains("wemacro") else { return }
            self.tryAutoConnect(device)
        }
        link.onLog = { [weak self] in self?.append($0) }
        link.onData = { [weak self] in self?.receive($0) }
        link.onDisconnect = { [weak self] in self?.stop(disconnected: true) }
        if scanAtStartup { scanAtLaunch() }
    }
    func append(_ line: String) { log.append(String(format: "%.3f ", Date().timeIntervalSince1970) + line); if log.count > 500 { log.removeFirst(log.count - 500) } }
    // A single controller is connected at a time: wired USB first, then BLE.
    func scanAtLaunch() {
        if autoConnectEnabled && !link.availableUSBDevices().isEmpty {
            kind = "USB"
            scan()
            if link.connected { return }
        }
        kind = "蓝牙"
        scan()
    }
    func scan() {
        guard !link.connected, !busy else { return }
        autoConnectionAttempted = false
        selected = kind == "模拟" ? "demo" : ""
        link.scan(kind)
        if kind == "USB" {
            for device in link.devices {
                tryAutoConnect(device)
                if link.connected { break }
            }
        }
    }
    private func tryAutoConnect(_ device: RailTransport.Device) {
        guard autoConnectEnabled, !link.connected, !busy, !autoConnectionAttempted else { return }
        autoConnectionAttempted = true
        selected = device.id
        do {
            configuredPacket = nil; parser = ReplyParser()
            try link.connect(device.id, kind: kind)
            position = 0; start = nil; end = nil
            phase = "连接后可直接移动并设置起终点"
            append("自动连接 · \(kind) · \(device.name)")
        } catch {
            autoConnectionAttempted = false
            append("自动连接失败 · \(device.name) · \(error.localizedDescription)")
        }
    }
    func toggleConnection() {
        if link.connected { autoConnectionAttempted = true; stop(); link.disconnect(); return }
        do { configuredPacket = nil; parser = ReplyParser(); try link.connect(selected, kind: selected == "demo" ? "模拟" : kind); position = 0; start = nil; end = nil; phase = "连接后可直接移动并设置起终点" }
        catch { self.error = error.localizedDescription }
    }
    func receive(_ data: Data) {
        append("RX " + data.map { String(format: "%02X", $0) }.joined(separator: " "))
        for event in parser.feed(data) where event == 0xf5 || event == 0xf6 {
            if let completion {
                self.completion = nil; moveTimeout?.cancel(); completion.resume()
            }
        }
    }
    func resetCaptureCompletion() {
        guard captureFinished, !busy else { return }
        captureFinished = false
        completed = 0
        shotsTaken = 0
        start = nil
        end = nil
        phase = "就绪"
    }
    func clearCaptureData() {
        guard !busy else { return }
        start = nil
        end = nil
        completed = 0
        shotsTaken = 0
        captureFinished = false
        phase = "数据已清空，请重新设置起终点"
    }
    func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy, link.connected else { return }
        do { try settings.validate() } catch { self.error = error.localizedDescription; return }
        resetCaptureCompletion()
        busy = true; paused = false
        let id = UUID(); token = id
        sleepAssertion = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "WeMacro 拍摄")
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await action(); if self.token == id { self.phase = "完成" } }
            catch is CancellationError { }
            catch {
                guard self.token == id else { return }
                self.configuredPacket = nil; self.link.emergencyStop(); self.position = 0; self.start = nil; self.end = nil
                self.error = error.localizedDescription; self.phase = "流程已停止，请重新设置起终点"
            }
            if self.token == id {
                self.busy = false; self.paused = false; self.operation = nil; self.finishActivity()
            }
        }
    }
    func finishActivity() { if let sleepAssertion { ProcessInfo.processInfo.endActivity(sleepAssertion); self.sleepAssertion = nil } }
    func delay(_ seconds: Double) async throws {
        try Task.checkCancellation()
        try await Task.sleep(for: .seconds(seconds))
        try Task.checkCancellation()
    }
    func move(_ delta: Int, using s: RailSettings, continuous: Bool = false) async throws {
        try Task.checkCancellation()
        guard delta != 0 else { return }
        let destination = position + delta
        guard abs(delta) <= 0xffffff else { throw RailError("运动脉冲数超出协议范围") }
        // Restore speed mode explicitly; movement packets below never request an automatic shutter.
        let config = try RailProtocol.frame(0x80, mode: s.microns ? 0 : 255, pulses: s.stepPulses)
        if configuredPacket != config {
            try link.send(config)
            // Keep the configuration transaction separate from movement on older HC-08 controllers.
            try await delay(0.3)
            configuredPacket = config
        }
        if continuous && !holding { return }
        parser = ReplyParser()
        let packet = try RailProtocol.frame(delta > 0 ? 0x40 : 0x41, pulses: abs(delta))
        phase = "移动中…"
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            completion = c
            do { try link.send(packet) }
            catch { completion = nil; c.resume(throwing: error); return }
            let deadline = max(5, Double(abs(delta)) / 6400 / (s.microns ? 0.1 : 2) + 5)
            moveTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(deadline)) } catch { return }
                guard let self, let continuation = self.completion else { return }
                self.completion = nil
                continuation.resume(throwing: RailError("未收到运动完成回复，已停止。请导出通信日志核对控制器固件。"))
            }
        }
        try Task.checkCancellation(); position = destination
        append("运动完成事件已识别 · position=\(position)")
        if !continuous { try await delay(0.1) }
    }
    func jog(_ direction: Int, large: Bool = false) {
        guard !busy, link.connected else { return }
        resetCaptureCompletion()
        let s = settings
        perform { [self] in try await move(direction * (large ? s.stepPulses * 10 : s.stepPulses), using: s) }
    }
    func beginStepHold(_ direction: Int) {
        guard !busy, link.connected, !controlsBlocked else { return }
        do { try settings.validate() } catch { self.error = error.localizedDescription; return }
        let s = settings
        steppingHeld = true
        let repeatAfter = ProcessInfo.processInfo.systemUptime + 0.35
        perform { [self] in
            defer { steppingHeld = false }
            // A tap always finishes one exact step. Holding repeats only after its reply.
            try await move(direction * s.stepPulses, using:s)
            let wait = repeatAfter - ProcessInfo.processInfo.systemUptime
            if steppingHeld && wait > 0 { try await delay(wait) }
            while steppingHeld && !controlsBlocked {
                try await move(direction * s.stepPulses, using:s)
            }
        }
    }
    func endStepHold() { steppingHeld = false }
    func beginHold(_ direction: Int) {
        guard !busy, link.connected else { return }
        resetCaptureCompletion()
        do { try settings.validate() } catch { self.error = error.localizedDescription; return }
        var s = settings
        s.microns = false; s.step = 0.5
        let initialPosition = position
        // Keep a long-running protocol command active until the user releases the control.
        let pulses = 0xffffff
        holding = true; holdStopRequested = false
        perform { [self] in
            defer { holding = false; holdStarted = nil; link.simulatingContinuous = false }
            let config = try RailProtocol.frame(0x80, mode: 255, pulses: s.stepPulses)
            if configuredPacket != config {
                try link.send(config); try await delay(0.3); configuredPacket = config
            }
            guard holding else { return }
            parser = ReplyParser()
            let packet = try RailProtocol.frame(direction > 0 ? 0x40 : 0x41, pulses: min(pulses, 0xffffff))
            phase = "连续快速移动中 · 按 Esc 停止"
            link.simulatingContinuous = true
            holdStarted = ProcessInfo.processInfo.systemUptime
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                completion = c
                do { try link.send(packet) } catch { completion = nil; c.resume(throwing: error); return }
                armHoldTimeout(Double(pulses) / 6400 / 3.546 + 5)
            }
            try Task.checkCancellation()
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime - (holdStarted ?? ProcessInfo.processInfo.systemUptime))
            let travelled = holdStopRequested ? min(pulses, Int((elapsed * 3.546 * 6400).rounded())) : pulses
            position = initialPosition + direction * travelled
            positionEstimated = positionEstimated || holdStopRequested
            append("连续运动结束 · \(holdStopRequested ? "按时长估算" : "达到命令终点") · position=\(position) elapsed=\(elapsed)")
        }
    }
    private func armHoldTimeout(_ seconds: Double) {
        moveTimeout?.cancel()
        moveTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, let c = self.completion else { return }
            self.completion = nil
            self.link.emergencyStop()
            c.resume(throwing: RailError("未收到连续运动停止确认，已再次请求停止；请重新设置起终点"))
        }
    }
    func endHold() {
        guard holding else { return }
        holding = false
        guard holdStarted != nil, !holdStopRequested else { return }
        holdStopRequested = true
        link.emergencyStop()
        phase = "正在等待停止确认…"
        armHoldTimeout(3)
    }
    func markStart() {
        guard link.connected, !busy else { return }
        resetCaptureCompletion()
        let origin = position
        // Rebase every recorded coordinate together so an existing endpoint stays fixed.
        end = end.map { $0 - origin }
        position = 0
        start = 0
        completed = 0
        shotsTaken = 0
        phase = end == nil ? "起点已设为 0，请设置终点" : "起终点已设置"
    }
    func markEnd() {
        guard link.connected, !busy else { return }
        resetCaptureCompletion()
        end = position
        completed = 0
        shotsTaken = 0
        phase = start == nil ? "终点已设置，请设置起点" : "起终点已设置"
    }
    func go(_ target: Int?) {
        guard !busy, link.connected else { return }
        resetCaptureCompletion()
        guard let target else { return }; let s = settings
        perform { [self] in try await move(target - position, using: s) }
    }
    func calibrate(using s: RailSettings, direction: Int = 1) async throws {
        let p = Int(ceil(s.backlash / 1000 * 6400))
        guard p > 0 else { return }
        try await move(-direction * p, using: s); try await move(direction * p, using: s)
    }
    func calibrate() { let s = settings; perform { [self] in try await calibrate(using: s) } }
    func shutter() { perform { [self] in try link.send(RailProtocol.frame(0x04)); try await delay(settings.interval) } }
    func run() {
        guard !busy, canRun else { return }
        do { try settings.validate() } catch { self.error = error.localizedDescription; return }
        if start == nil { markStart() }
        else if end == nil { markEnd() }
        guard let a = start, let b = end, a != b else { return }
        let s = settings
        let origin = captureEndToStart ? b : a
        let destination = captureEndToStart ? a : b
        perform { [self] in
            shotsTaken = 0
            capturing = true
            defer { capturing = false }
            try await move(origin - position, using: s)
            let direction = destination > origin ? 1 : -1
            if s.compensate { try await calibrate(using: s, direction: direction) }
            completed = 0
            shotsTaken = 0
            let count = Int(ceil(Double(abs(b - a)) / Double(s.stepPulses)))
            for index in 0...count {
                while paused { phase = "已暂停"; try await delay(0.05) }
                let target = origin + direction * min(index * s.stepPulses, abs(b - a))
                try await move(target - position, using: s)
                phase = "运动后稳定 · 第 \(index + 1)/\(count + 1) 组"
                try await delay(s.settling)
                for shot in 0..<s.shutters {
                    phase = "拍摄 \(index + 1)/\(count + 1) · 快门 \(shot + 1)"
                    try link.send(RailProtocol.frame(0x04))
                    shotsTaken += 1
                    try await delay(s.interval)
                }
                completed = index + 1
            }
            if s.returnToStart { try await move(a - position, using: s) }
            if s.beep {
                try link.send(RailProtocol.frame(0x12))
                append("拍摄完成 · 已发送设备蜂鸣指令")
            }
            saveDefaults()
            captureFinished = true
        }
    }
    func stop(disconnected: Bool = false) {
        steppingHeld = false
        holding = false; holdStarted = nil; link.simulatingContinuous = false; positionEstimated = false; configuredPacket = nil; token = UUID(); operation?.cancel(); operation = nil; moveTimeout?.cancel()
        if let completion { self.completion = nil; completion.resume(throwing: CancellationError()) }
        if !disconnected { link.emergencyStop() }
        captureFinished = false
        busy = false; paused = false; capturing = false; completed = 0; shotsTaken = 0; position = 0; start = nil; end = nil; finishActivity()
        phase = disconnected ? "连接已断开，位置已清除" : "已停止，可重新移动并设置起终点"
    }
    func saveDefaults() { guard persistSettings else { return }; if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: "settings.v01") } }
    func save() {
        do {
            try settings.validate()
            let p = NSSavePanel(); p.nameFieldStringValue = "WeMacro-settings.json"; p.allowedContentTypes = [.json]
            if p.runModal() == .OK, let url = p.url { try JSONEncoder().encode(settings).write(to: url); saveDefaults() }
        } catch { self.error = error.localizedDescription }
    }
    func load() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url {
            do { let s = try JSONDecoder().decode(RailSettings.self, from: Data(contentsOf: url)); try s.validate(); settings = s; saveDefaults() }
            catch { self.error = error.localizedDescription }
        }
    }
    func exportLog() {
        let p = NSSavePanel(); p.nameFieldStringValue = "WeMacro-communication.txt"
        if p.runModal() == .OK, let url = p.url { do { try log.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription } }
    }
}
