import Foundation
import MemoryCore
var sample = MMMemory()
guard mm_read_memory(&sample) else { fatalError("host_statistics64 failed") }
precondition(sample.total == ProcessInfo.processInfo.physicalMemory)
precondition(sample.wired > 0 && sample.app > 0)
precondition(sample.app + sample.wired + sample.compressed <= sample.total)
guard sample.swap_valid else {
    fputs("FAIL: vm.swapusage is unavailable. Run this read-only diagnostic outside the Codex development sandbox.\n", stderr)
    exit(2)
}
var rows = [MMProcess](repeating: MMProcess(), count: 5)
let count = Int(mm_read_processes(&rows, 5))
precondition(count > 0 && count <= 5)
for i in 0..<max(0, count - 1) { precondition(rows[i].footprint >= rows[i + 1].footprint) }
for i in 0..<count { precondition(rows[i].pid > 0 && rows[i].footprint > 0) }
let started = Date()
for _ in 0..<100 { precondition(mm_read_memory(&sample)) }
print("PASS: live VM snapshot, physical total, component bounds, swap, sorted readable processes; 100 samples in \(Date().timeIntervalSince(started))s")
print("total=\(sample.total) app=\(sample.app) wired=\(sample.wired) compressed=\(sample.compressed) cached=\(sample.cached) swap=\(sample.swap) pressure=\(sample.pressure)")
for i in 0..<count { var name = rows[i].name; let text = withUnsafePointer(to: &name) { $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) } }; print("\(rows[i].pid) \(text) \(rows[i].footprint)") }
