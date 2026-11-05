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
    }
}
