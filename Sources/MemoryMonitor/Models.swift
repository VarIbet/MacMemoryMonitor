import Foundation
import AppKit
import Combine
import MemoryCore
import UserNotifications

let gib = 1_073_741_824.0
func memoryText(_ bytes: UInt64, precision: Int = 1) -> String {
    String(format: "%.*f GB", precision, Double(bytes) / gib)
}
enum Pressure: String { case normal = "Normal", warning = "Warning", critical = "Critical", unknown = "等待系统状态" }
struct Snapshot {
    let time: Date
    let raw: MMMemory
    var used: UInt64 { min(raw.total, raw.app + raw.wired + raw.compressed) }
    var available: UInt64 { raw.total - used }
    var fraction: Double { raw.total > 0 ? Double(used) / Double(raw.total) : 0 }
}
struct HistoryPoint: Identifiable {
    let time: Date
    let bytes: Double
    let pressure: Pressure
    var id: Date { time }
}
/// One minute buckets for 24h, ten second buckets for 1h, raw samples for 5m.
struct HistoryStore {
    private(set) var recent: [HistoryPoint] = []
    private(set) var medium: [HistoryPoint] = []
    private(set) var long: [HistoryPoint] = []
    mutating func append(_ point: HistoryPoint) {
        recent.append(point)
        recent.removeAll { point.time.timeIntervalSince($0.time) > 300 }
        add(point, to: &medium, interval: 10, retention: 3600)
        add(point, to: &long, interval: 60, retention: 86400)
    }
    private func bucket(_ point: HistoryPoint, _ interval: Double) -> Int { Int(point.time.timeIntervalSince1970 / interval) }
    private func add(_ point: HistoryPoint, to values: inout [HistoryPoint], interval: Double, retention: Double) {
        if let last = values.last, bucket(last, interval) == bucket(point, interval) { values[values.count - 1] = point }
        else { values.append(point) }
        values.removeAll { point.time.timeIntervalSince($0.time) > retention }
    }
    func points(for seconds: Double) -> [HistoryPoint] { seconds <= 300 ? recent : seconds <= 3600 ? medium : long }
}
struct ProcessRow: Identifiable {
    let id: Int32
    let name: String
    let bytes: UInt64
    let icon: NSImage?
}
@MainActor final class Preferences: ObservableObject {
    @Published var interval: Double { didSet { save(interval, "interval") } }
    @Published var unit: String { didSet { save(unit, "unit") } }
    @Published var precision: Int { didSet { save(precision, "precision") } }
    @Published var appearance: String { didSet { save(appearance, "appearance") } }
    @Published var notifications: Bool { didSet { save(notifications, "notifications") } }
    private func save(_ value: Any, _ key: String) { UserDefaults.standard.set(value, forKey: key) }
    init() {
        let d = UserDefaults.standard
        let i = d.double(forKey: "interval"); interval = [1.0,2,5,10].contains(i) ? i : 2
        unit = d.string(forKey: "unit") == "%" ? "%" : "GB"
        precision = d.object(forKey: "precision") == nil ? 1 : min(2, max(0, d.integer(forKey: "precision")))
        appearance = d.string(forKey: "appearance") ?? "system"
        notifications = d.bool(forKey: "notifications")
    }
}
@MainActor final class MonitorModel: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var pressure: Pressure = .unknown
    @Published var pressureSource = "等待系统内存压力事件"
    @Published var history = HistoryStore()
    @Published var processes: [ProcessRow] = []
    @Published var error: String?
    @Published var processDate: Date?
    @Published var notificationStatus: String?
    let preferences = Preferences()
    var onUpdate: (() -> Void)?
    private var source: DispatchSourceMemoryPressure?
    private var timer: DispatchSourceTimer?
    private let worker = DispatchQueue(label: "local.memorymonitor.sampler", qos: .utility)
    private var sampling = false
    private var scanning = false
    private var sleeping = false
    var panelVisible = false
    private var lastProcessScan = Date.distantPast
    private var criticalSince: Date?
    private var lastNotification = Date.distantPast
    private var hasPressureEvent = false
    private var cancellables = Set<AnyCancellable>()
    init() {
        let s = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        s.setEventHandler { [weak self, weak s] in
            guard let self, let flags = s?.data else { return }
            self.hasPressureEvent = true
            self.pressure = flags.contains(.critical) ? .critical : flags.contains(.warning) ? .warning : .normal
            self.pressureSource = "系统 Dispatch 内存压力事件"
            self.onUpdate?()
        }
        source = s; s.resume()
        preferences.$interval.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.schedule() } }.store(in: &cancellables)
        preferences.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.onUpdate?() } }.store(in: &cancellables)
        schedule()
    }
    func schedule() {
        timer?.cancel()
        guard !sleeping else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: preferences.interval, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in self?.sample() }
        timer = t; t.resume()
    }
    func sleep() { sleeping = true; timer?.cancel(); timer = nil; criticalSince = nil }
    func wake() { sleeping = false; lastProcessScan = .distantPast; schedule() }
    func sample() {
        guard !sampling, !sleeping else { return }; sampling = true
        worker.async { [weak self] in
            var raw = MMMemory(); let ok = mm_read_memory(&raw)
            DispatchQueue.main.async {
                guard let self else { return }; self.sampling = false
                guard ok else { self.error = "无法读取系统内存，正在重试"; self.onUpdate?(); return }
                self.error = nil
                let snap = Snapshot(time: Date(), raw: raw); self.snapshot = snap
                if !self.hasPressureEvent {
                    switch raw.pressure { case 1: self.pressure = .normal; case 2: self.pressure = .warning; case 4: self.pressure = .critical; default: self.pressure = .unknown }
                    self.pressureSource = raw.pressure == 0 ? "等待系统事件；启动状态不可读取" : "内核压力等级（兼容性读取）"
                }
                self.history.append(HistoryPoint(time: snap.time, bytes: Double(snap.used), pressure: self.pressure))
                self.checkNotification(); self.onUpdate?()
                if self.panelVisible { self.scanProcesses() }
            }
        }
    }
    func scanProcesses() {
        guard !scanning, !sleeping, Date().timeIntervalSince(lastProcessScan) >= 10 else { return }
        scanning = true; lastProcessScan = Date()
        worker.async { [weak self] in
            var entries = [MMProcess](repeating: MMProcess(), count: 5)
            let count = mm_read_processes(&entries, 5)
            let results = entries.prefix(Int(count)).map { entry -> (Int32, String, UInt64) in
                var name = entry.name
                let text = withUnsafePointer(to: &name) { $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) } }
                return (entry.pid, text, entry.footprint)
            }
            DispatchQueue.main.async {
                guard let self else { return }; self.scanning = false
                self.processes = results.map { pid, name, bytes in
                    let app = NSRunningApplication(processIdentifier: pid)
                    return ProcessRow(id: pid, name: app?.localizedName ?? name, bytes: bytes, icon: app?.icon)
                }
                self.processDate = Date()
            }
        }
    }
    func requestNotifications(_ enabled: Bool) {
        preferences.notifications = enabled
        guard enabled else { criticalSince = nil; return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.notificationStatus = error?.localizedDescription ?? (granted ? "通知已启用：严重压力持续 60 秒后提醒，冷却 30 分钟。" : "通知权限未开启，请在系统设置中允许。")
                if !granted { self?.preferences.notifications = false }
            }
        }
    }
    private func checkNotification() {
        guard preferences.notifications, pressure == .critical else { criticalSince = nil; return }
        let now = Date()
        if criticalSince == nil { criticalSince = now }
        guard now.timeIntervalSince(criticalSince!) >= 60, now.timeIntervalSince(lastNotification) >= 1800 else { return }
        lastNotification = now
        let content = UNMutableNotificationContent()
        content.title = "内存压力持续偏高"; content.body = "系统已持续 60 秒报告严重内存压力，可打开活动监视器查看。"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "memory-pressure", content: content, trigger: nil))
    }
}
