import Foundation
import CoreBluetooth
import Darwin

@MainActor final class RailTransport: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published var devices: [Device] = []
    @Published var connected = false
    @Published var status = "未连接"
    struct Device: Identifiable, Hashable { let id: String; let name: String }
    var simulatingContinuous = false
    var onDevice: ((Device) -> Void)?
    var onData: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var onLog: ((String) -> Void)?
    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var peripherals: [String: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var descriptor: Int32 = -1
    private var poller: Timer?
    private var timeout: Timer?
    private var scanTimer: Timer?
    private var simulated = false
    private var queue: [Data] = []
    private var waitingWrite = false
    private var scanPending = false
    private var bluetoothInitialized = false
    private var scanningBluetooth = false
    override init() { super.init() }
    func scan(_ kind: String) {
        if bluetoothInitialized { central.stopScan() }
        scanTimer?.invalidate(); scanPending = false
        scanningBluetooth = kind == "蓝牙"
        devices = []
        if kind == "模拟" { devices = [.init(id: "demo", name: "模拟滑轨（不发送硬件指令）")]; status = "请选择模拟滑轨"; return }
        if kind == "USB" {
            devices = availableUSBDevices()
            status = devices.isEmpty ? "未发现 USB 串口" : "请选择 USB 设备"; return
        }
        bluetoothInitialized = true
        guard central.state == .poweredOn else { scanPending = true; updateBluetoothStatus(); return }
        scanPending = false
        central.stopScan()
        onLog?("BLE scanning · authorization=\(CBCentralManager.authorization.rawValue)")
        status = "扫描蓝牙…"; central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }
                self.central.stopScan(); self.scanningBluetooth = false
                if self.devices.isEmpty {
                    self.status = self.availableUSBDevices().isEmpty
                        ? "未发现USB/蓝牙设备"
                        : "未发现 BLE 设备，请确认 HC-08 未被其他应用连接"
                } else {
                    self.status = "扫描完成 · \(self.devices.count) 个设备"
                }
                self.onLog?(self.status) }
        }
    }
    func availableUSBDevices() -> [Device] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names.filter { $0.hasPrefix("cu.") && ($0.lowercased().contains("usb") || $0.lowercased().contains("wch")) }
            .sorted().map { .init(id: "/dev/" + $0, name: $0) }
    }
    func connect(_ id: String, kind: String) throws {
        disconnect()
        if kind == "模拟" || id == "demo" { simulated = true; connected = true; status = "测试假设备已连接（模拟）"; return }
        if kind == "USB" {
            descriptor = Darwin.open(id, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard descriptor >= 0 else { throw RailError("无法打开串口：\(String(cString: strerror(errno)))") }
            var options = termios()
            guard tcgetattr(descriptor, &options) == 0 else { disconnect(); throw RailError("无法读取串口参数") }
            cfmakeraw(&options); cfsetispeed(&options, speed_t(B9600)); cfsetospeed(&options, speed_t(B9600))
            options.c_cflag &= ~tcflag_t(CSIZE | PARENB | CSTOPB | CRTSCTS)
            options.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
            guard tcsetattr(descriptor, TCSANOW, &options) == 0 else { disconnect(); throw RailError("无法配置 9600/8N1 串口") }
            connected = true; status = "USB 已连接 · 9600"
            poller = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
            return
        }
        guard let p = peripherals[id] else { throw RailError("请重新扫描并选择设备") }
        central.stopScan(); scanningBluetooth = false; peripheral = p; p.delegate = self
        status = "正在连接…"; central.connect(p)
        timeout = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.disconnect() } }
    }
    func disconnect() {
        timeout?.invalidate(); poller?.invalidate(); scanTimer?.invalidate(); if bluetoothInitialized { central.stopScan() }; scanPending = false; scanningBluetooth = false
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil; characteristic = nil; queue = []; waitingWrite = false
        let wasConnected = connected; connected = false; simulated = false; status = "未连接"
        if wasConnected { onDisconnect?() }
    }
    private func poll() {
        var b = [UInt8](repeating: 0, count: 256)
        let n = Darwin.read(descriptor, &b, b.count)
        if n > 0 { onData?(Data(b.prefix(n))) }
        else if n < 0 && errno != EAGAIN && errno != EWOULDBLOCK { disconnect() }
    }
    func send(_ data: Data) throws {
        guard connected else { throw RailError("请先连接设备") }
        onLog?("TX " + data.map { String(format: "%02X", $0) }.joined(separator: " "))
        if simulated {
            if !simulatingContinuous && (data[2] == 0x40 || data[2] == 0x41) {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(50))
                    if self?.simulated == true { self?.onData?(Data([0x5a, 0xa5, 0xf5])) }
                }
            }
            if data[2] == 0x20 && simulatingContinuous {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(20))
                    self?.onData?(Data([0x5a, 0xa5, 0xf6]))
                }
            }
            return
        }
        if descriptor >= 0 {
            let n = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            guard n == data.count else { throw RailError("串口写入不完整，已停止流程") }; return
        }
        guard characteristic != nil else { throw RailError("蓝牙写入特征未就绪") }
        queue.append(data); pump()
    }
    private func pump() {
        guard !waitingWrite, !queue.isEmpty, let p = peripheral, let c = characteristic else { return }
        let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
        if type == .withoutResponse && !p.canSendWriteWithoutResponse { return }
        waitingWrite = type == .withResponse
        let data = queue.removeFirst()
        onLog?("BLE write \(type == .withResponse ? "withResponse" : "withoutResponse") · " + data.map { String(format: "%02X", $0) }.joined(separator: " "))
        p.writeValue(data, for: c, type: type)
        if !waitingWrite { pump() }
    }
    func emergencyStop() {
        queue = []
        if let d = try? RailProtocol.frame(0x20) { try? send(d) }
    }
    private func updateBluetoothStatus() {
        switch central.state {
        case .poweredOff: status = "系统蓝牙已关闭"
        case .unauthorized: status = "蓝牙未授权：请在系统设置 → 隐私与安全性 → 蓝牙中允许 WeMacro"
        case .unsupported: status = "此 Mac 不支持 BLE"
        case .resetting: status = "系统蓝牙正在重置"
        case .unknown: status = "蓝牙正在初始化…"
        case .poweredOn: status = "蓝牙已就绪"
        @unknown default: status = "未知蓝牙状态"
        }
        onLog?("BLE state=\(central.state.rawValue) authorization=\(CBCentralManager.authorization.rawValue) · " + status)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard scanningBluetooth || peripheral != nil else { return }
        updateBluetoothStatus()
        if central.state == .poweredOn && scanPending { scan("蓝牙") }
        else if central.state != .poweredOn, connected, peripheral != nil { disconnect(); updateBluetoothStatus() }
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard scanningBluetooth, !connected else { return }
        let id = p.identifier.uuidString
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? "未命名 BLE · " + String(id.prefix(8))
        peripherals[id] = p
        let device = Device(id: id, name: name)
        if let index = devices.firstIndex(where: { $0.id == id }) {
            if devices[index].name != name { devices[index] = device }
        } else {
            devices.append(device)
            onLog?("BLE found: \(name) id=\(id) RSSI=\(rssi) adv=\(advertisementData)")
        }
        status = "扫描蓝牙… 已发现 \(devices.count) 个设备"
        onDevice?(device)
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices(nil) }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { disconnect(); status = error?.localizedDescription ?? "蓝牙连接失败" }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard peripheral?.identifier == p.identifier else { return }; disconnect()
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { disconnect(); return }
        for s in peripheral.services ?? [] where s.uuid == CBUUID(string: "FFE0") { peripheral.discoverCharacteristics(nil, for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { disconnect(); return }
        for c in service.characteristics ?? [] where c.uuid == CBUUID(string: "FFE1") {
            guard c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) else { continue }
            characteristic = c
            guard c.properties.contains(.notify) || c.properties.contains(.indicate) else { status = "设备无运动通知能力，暂不连接"; central.cancelPeripheralConnection(p); return }
            p.setNotifyValue(true, for: c)
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard error == nil, c.isNotifying else { disconnect(); return }
        timeout?.invalidate(); connected = true; status = "蓝牙已连接 · \(p.name ?? "HC-08")"
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard error == nil, let d = c.value else { return }; onData?(d)
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        waitingWrite = false
        onLog?("BLE write callback: " + (error?.localizedDescription ?? "OK"))
        if error != nil { disconnect() } else { pump() }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { pump() }
}
