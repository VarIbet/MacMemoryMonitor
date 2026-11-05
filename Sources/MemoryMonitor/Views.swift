import SwiftUI
import Charts
import ServiceManagement

extension Pressure {
    var color: Color { switch self { case .normal: return .green; case .warning: return .yellow; case .critical: return .red; case .unknown: return .secondary } }
}
struct DashboardView: View {
    @ObservedObject var model: MonitorModel
    let settings: () -> Void
    @State private var range: Double = 300
    @State private var showMethod = false
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Memory Monitor").font(.headline)
                Spacer()
                Circle().fill(model.pressure.color).frame(width: 7, height: 7)
                Text(model.pressure.rawValue).font(.caption).foregroundStyle(.secondary)
            }.help(model.pressureSource)
            if let s = model.snapshot {
                overview(s)
                Divider()
                metrics(s)
                Divider()
                history(s)
                Divider()
                processes
            } else { ProgressView("正在读取系统内存…").frame(maxWidth: .infinity, minHeight: 180) }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack(spacing: 12) {
                Button { AppLifecycleManager.openActivityMonitor() } label: { Label("活动监视器", systemImage: "waveform.path.ecg") }
                Spacer()
                Button(action: settings) { Image(systemName: "gearshape") }.help("偏好设置")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("退出应用")
            }.buttonStyle(.borderless).font(.caption)
        }
        .padding(20).frame(width: 370)
        .background(.regularMaterial)
    }
    private func overview(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(memoryText(s.used)).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("已使用 · 约").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(s.fraction, format: .percent.precision(.fractionLength(0))).font(.title3).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(.blue).frame(width: geo.size.width * Double(s.raw.app) / Double(s.raw.total))
                    Rectangle().fill(.orange).frame(width: geo.size.width * Double(s.raw.wired) / Double(s.raw.total))
                    Rectangle().fill(.purple).frame(width: geo.size.width * Double(s.raw.compressed) / Double(s.raw.total))
                    Rectangle().fill(Color.secondary.opacity(0.16))
                }.clipShape(Capsule())
            }.frame(height: 8).accessibilityLabel("内存使用率 \(Int(s.fraction * 100))%")
            HStack {
                Text("物理内存 \(memoryText(s.raw.total, precision: 0))")
                Spacer()
                Text("可用约 \(memoryText(s.available))")
            }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
    private func metrics(_ s: Snapshot) -> some View {
        VStack(spacing: 8) {
            metric("应用内存（约）", value: memoryText(s.raw.app), color: .blue)
            metric("联动内存 · Wired", value: memoryText(s.raw.wired), color: .orange)
            metric("压缩内存", value: memoryText(s.raw.compressed), color: .purple)
            metric("缓存文件（约）", value: memoryText(s.raw.cached), color: .gray)
            metric("交换内存 · Swap", value: s.raw.swap_valid ? memoryText(s.raw.swap) : "不可用", color: .secondary)
            Button { showMethod.toggle() } label: { Label("统计口径与内存压力", systemImage: "info.circle").font(.caption) }.buttonStyle(.plain).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            if showMethod {
                Text("已用 ≈ 匿名驻留 − 可清除 + Wired + 压缩器实际占用；可用 = 总量 − 已用。缓存是可回收资源，不代表性能问题。GB 按 1024³ 字节显示。统一内存不重复加算 GPU。\n压力来源：\(model.pressureSource)。颜色来自系统压力等级，不按使用率判断。排行榜采用 phys_footprint，可能与活动监视器不同，受保护进程会跳过。")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func metric(_ name: String, value: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.system(size: 12))
    }
    private func history(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("使用趋势").font(.subheadline.weight(.medium))
                Spacer()
                Picker("时间范围", selection: $range) { Text("5 分钟").tag(300.0); Text("1 小时").tag(3600.0); Text("24 小时").tag(86400.0) }.labelsHidden().frame(width: 112)
            }
            Chart(model.history.points(for: range)) { point in
                LineMark(x: .value("时间", point.time), y: .value("GB", point.bytes / gib))
                    .interpolationMethod(.monotone).foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 1.8))
            }
            .chartYScale(domain: 0...(Double(s.raw.total) / gib))
            .chartXScale(domain: s.time.addingTimeInterval(-range)...s.time)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in AxisGridLine(); AxisValueLabel { if let n = value.as(Double.self) { Text("\(n, specifier: "%.0f") GB").font(.system(size: 9)) } } } }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.hour().minute()) } }
            .frame(height: 95)
        }
    }
    private var processes: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text("占用排行").font(.subheadline.weight(.medium)); Spacer(); Text("进程 · 每 10 秒").font(.caption2).foregroundStyle(.secondary) }
            if model.processes.isEmpty { Text(model.processDate == nil ? "正在读取进程…" : "暂无可读取的进程").font(.caption).foregroundStyle(.secondary) }
            ForEach(model.processes) { process in
                HStack(spacing: 8) {
                    Group { if let icon = process.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "app.dashed").resizable() } }.frame(width: 20, height: 20)
                    Text(process.name).lineLimit(1).help("PID \(process.id)")
                    Spacer(minLength: 8)
                    Text(memoryText(process.bytes, precision: 2)).foregroundStyle(.secondary).monospacedDigit()
                }.font(.system(size: 12))
            }
        }
    }
}
struct PreferencesView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var preferences: Preferences
    @State private var loginStatus = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("基本设置") {
                Toggle("登录时自动启动", isOn: Binding(get: { loginStatus }, set: setLogin))
                Picker("自动刷新", selection: $preferences.interval) { ForEach([1.0,2,5,10], id: \.self) { Text("\(Int($0)) 秒").tag($0) } }
                Picker("菜单栏单位", selection: $preferences.unit) { Text("GB").tag("GB"); Text("百分比").tag("%") }
                Picker("小数位数", selection: $preferences.precision) { ForEach(0...2, id: \.self) { Text("\($0) 位").tag($0) } }
            }
            Section("外观") {
                Picker("显示模式", selection: $preferences.appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
            }
            Section("通知") {
                Toggle("持续高内存压力时提醒", isOn: Binding(get: { preferences.notifications }, set: model.requestNotifications))
                Text("仅在严重压力持续 60 秒后提醒，两次提醒至少间隔 30 分钟。").font(.caption).foregroundStyle(.secondary)
                if let status = model.notificationStatus { Text(status).font(.caption) }
            }
            if let message { Text(message).foregroundStyle(.secondary).font(.caption) }
            Text("所有监控均在本机完成。无账户、无上传、无网络请求。\nMemory Monitor 1.0 · Apple Silicon · macOS 14+").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).frame(width: 460, height: 500)
        .onAppear { refreshLogin() }
    }
    private func refreshLogin() { loginStatus = SMAppService.mainApp.status == .enabled }
    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLogin()
            if SMAppService.mainApp.status == .requiresApproval { message = "请在系统设置 → 通用 → 登录项中允许 Memory Monitor。" }
            else { message = nil }
        } catch { refreshLogin(); message = "无法更改开机自启：\(error.localizedDescription)。请先将应用移动到 Applications 后重试。" }
    }
}
