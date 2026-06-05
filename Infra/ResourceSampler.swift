import Foundation
import Darwin

/// Samples this process's memory footprint for the diagnostics panel / README performance metrics.
///
/// IMPORTANT: Wren runs model inference in a SEPARATE subprocess (`ParrotCompletionHelper`), so the
/// model's RAM is NOT in this process. `appMemoryMB` reports only the main app. To get the total
/// (app + helper), add the helper's footprint — visible in Activity Monitor as
/// "ParrotCompletionHelper", or summed via `totalFootprintMB(includingChildren:)` when the helper
/// pid is known.
enum ResourceSampler {
    /// Resident/physical footprint of the current process in MB (Apple's `phys_footprint`, the same
    /// number Activity Monitor's "Memory" column shows). Returns 0 on failure.
    static func appMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }

    /// App footprint plus the resident size of a known child process (e.g. the completion helper),
    /// read via `proc_pid_rusage`. If `childPID` is nil or unreadable, returns just the app footprint.
    static func totalFootprintMB(childPID: pid_t?) -> Double {
        var total = appMemoryMB()
        if let pid = childPID, pid > 0 {
            var usage = rusage_info_current()
            let rc = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            if rc == 0 { total += Double(usage.ri_resident_size) / (1024 * 1024) }
        }
        return total
    }
}
