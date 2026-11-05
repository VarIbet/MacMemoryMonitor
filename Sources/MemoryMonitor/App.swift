import SwiftUI
import AppKit
import Combine

@main struct MemoryMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleManager.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
@MainActor final class AppLifecycleManager: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var item: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    let model = MonitorModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 92)
        item.button?.target = self; item.button?.action = #selector(togglePanel)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        popover = NSPopover(); popover.behavior = .transient; popover.animates = false; popover.delegate = self
        model.onUpdate = { [weak self] in self?.refresh() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.model.sleep() } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.model.wake() } })
        refresh()
        if CommandLine.arguments.contains("--show-dashboard") { DispatchQueue.main.async { self.togglePanel() } }
    }
    func refresh() {
        let p = model.preferences
        let color: NSColor
        switch model.pressure { case .normal: color = .systemGreen; case .warning: color = .systemYellow; case .critical: color = .systemRed; case .unknown: color = .secondaryLabelColor }
        let text: String
        if let s = model.snapshot { text = p.unit == "%" ? String(format: "%.*f%%", p.precision, s.fraction * 100) : memoryText(s.used, precision: p.precision) }
        else { text = "— GB" }
        let title = NSMutableAttributedString(string: "●", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 10)])
        title.append(NSAttributedString(string: "  " + text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]))
        item?.button?.attributedTitle = title
        item?.length = p.precision == 2 ? 100 : 92
        item?.button?.toolTip = "Memory Monitor · \(model.pressure.rawValue)\(model.error == nil ? "" : " · 数据暂不可用")"
        item?.button?.setAccessibilityLabel("已用内存 \(text)，压力 \(model.pressure.rawValue)")
        let appearance: NSAppearance? = p.appearance == "light" ? NSAppearance(named: .aqua) : p.appearance == "dark" ? NSAppearance(named: .darkAqua) : nil
        popover?.appearance = appearance; settingsWindow?.appearance = appearance
    }
    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        if popover.contentViewController == nil {
            popover.contentViewController = NSHostingController(rootView: DashboardView(model: model, settings: { [weak self] in self?.openSettings() }))
        }
        model.panelVisible = true; model.scanProcesses()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    func popoverDidClose(_ notification: Notification) { model.panelVisible = false }
    func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 500), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Memory Monitor 偏好设置"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: PreferencesView(model: model, preferences: model.preferences)); window.center()
            settingsWindow = window
        }
        refresh(); NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    static func openActivityMonitor() {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") ?? URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    func applicationWillTerminate(_ notification: Notification) { model.sleep(); for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
}
