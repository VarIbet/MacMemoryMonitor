import AppKit
import MemoryCore

/// Used only on the serial sampler queue. Cache is scoped to one ranking scan.
final class ProcessIconResolver {
    private var icons: [URL: NSImage] = [:]

    /// Prefer the outer app over nested Helper.app bundles which often have no icon.
    static func applicationURL(forExecutableURL executable: URL) -> URL? {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in executable.standardizedFileURL.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            if current.pathExtension.lowercased() == "app" { return current }
        }
        return nil
    }

    func icon(for pid: Int32) -> NSImage? {
        var candidate = pid
        var visited = Set<Int32>()
        for _ in 0..<8 {
            guard candidate > 1, visited.insert(candidate).inserted else { break }
            var identity = MMProcessIdentity()
            guard mm_read_process_identity(candidate, &identity) else { break }
            var buffer = identity.executable_path
            let path = withUnsafePointer(to: &buffer) {
                $0.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) }
            }
            if !path.isEmpty,
               let app = Self.applicationURL(forExecutableURL: URL(fileURLWithPath: path)),
               FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) {
                if let cached = icons[app] { return cached }
                let icon = NSWorkspace.shared.icon(forFile: app.path)
                icons[app] = icon
                return icon
            }
            candidate = identity.parent_pid
        }
        // Shared XPC services may have no publicly identifiable owner. Do not guess an app.
        return nil
    }
}
