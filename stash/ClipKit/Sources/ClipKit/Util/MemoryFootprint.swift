import Foundation
#if canImport(Darwin)
@preconcurrency import Darwin
#endif

/// Debug aid for the keyboard's memory ceiling. Reports numbers only, never content.
public enum MemoryFootprint {
    /// Physical footprint of this process, the figure the system's memory limits are based on.
    public static func currentBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// Bytes this process may still allocate before the system terminates it (iOS only).
    public static func availableBytes() -> UInt64? {
        #if os(iOS)
        let value = os_proc_available_memory()
        return value > 0 ? UInt64(value) : nil
        #else
        return nil
        #endif
    }

    public static func megabytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "n/a" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
