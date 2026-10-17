#if DEBUG
import Darwin
import Foundation

/// アプリの物理メモリ。`task_vm_info.phys_footprint` は、Jetsam が見る量に近い。
enum MemoryFootprint {
    static func bytes() -> UInt64 {
        var info = task_vm_info_data_t()
        // TASK_VM_INFO_COUNT はマクロなので、Swift からは同じ式を書く。
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }
}

/// 計測のあいだ、短い間隔で footprint を見て最大を残す。
final class FootprintMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64
    private var task: Task<Void, Never>?

    init(start: UInt64) {
        peak = start
    }

    func start() {
        task = Task.detached { [weak self] in
            while !Task.isCancelled {
                self?.record(MemoryFootprint.bytes())
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }

    func record(_ bytes: UInt64) {
        lock.lock()
        peak = max(peak, bytes)
        lock.unlock()
    }

    func stop() -> UInt64 {
        task?.cancel()
        task = nil
        record(MemoryFootprint.bytes())
        lock.lock()
        let value = peak
        lock.unlock()
        return value
    }
}

enum WallClock {
    /// 壁時計の差。CPU 時間ではない。時計の補正でずれることがある。
    static func seconds(from start: Date, to end: Date = Date()) -> Double {
        end.timeIntervalSince(start)
    }
}
#endif
