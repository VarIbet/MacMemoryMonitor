import Foundation
import MemoryCore
@main struct HistoryChecks {
    static func main() {
        var history = HistoryStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0...172800 {
            history.append(HistoryPoint(time: start.addingTimeInterval(Double(i)), bytes: Double(i), pressure: .normal))
        }
        precondition(history.recent.count == 301)
        precondition(history.medium.count <= 361)
        precondition(history.long.count <= 1441)
        precondition(history.points(for: 86400).last?.bytes == 172800)
        precondition(history.points(for: 300).first?.bytes == 172500)
        history.append(HistoryPoint(time: start.addingTimeInterval(300000), bytes: 42, pressure: .warning))
        precondition(history.recent.count == 1 && history.medium.count == 1 && history.long.count == 1)
        var raw = MMMemory(); raw.total = 16; raw.app = 7; raw.wired = 3; raw.compressed = 2
        let snapshot = Snapshot(time: start, raw: raw)
        precondition(snapshot.used == 12 && snapshot.available == 4 && snapshot.fraction == 0.75)
        raw.app = 20
        precondition(Snapshot(time: start, raw: raw).used == 16)
        print("PASS: 48h simulated history bounded at 301/361/1441 points, latest values, long sleep pruning, composition and saturation")
        let helper = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/Frameworks/Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper")
        precondition(ProcessIconResolver.applicationURL(forExecutableURL: helper)?.path == "/Applications/Google Chrome.app")
        let codex = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Frameworks/Codex Framework.framework/Helpers/Codex (Renderer).app/Contents/MacOS/Codex (Renderer)")
        precondition(ProcessIconResolver.applicationURL(forExecutableURL: codex)?.path == "/Applications/ChatGPT.app")
        precondition(ProcessIconResolver.applicationURL(forExecutableURL: URL(fileURLWithPath: "/usr/bin/top")) == nil)
        var invalid = MMProcessIdentity()
        precondition(!mm_read_process_identity(-1, &invalid))
        let resolver = ProcessIconResolver()
        var rows = [MMProcess](repeating: MMProcess(), count: 5)
        let count = Int(mm_read_processes(&rows, 5))
        for row in rows.prefix(count) {
            let icon = resolver.icon(for: row.pid)
            print("Live process icon: pid=\(row.pid) resolved=\(icon != nil)")
        }
        print("PASS: outer app icon selection, nested helper bundles, non-app path and invalid PID")
    }
}
