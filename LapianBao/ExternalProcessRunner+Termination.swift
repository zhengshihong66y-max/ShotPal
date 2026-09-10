import Darwin
import Foundation

extension ExternalProcessRunner {
    /// Only signal this Process and descendants observed while it was still running.
    /// Recheck each PID's birth time before escalation to avoid touching a reused PID.
    static func terminateTree(_ process: Process) {
        guard process.isRunning else { return }
        let parent = process.processIdentifier
        var descendants: [(pid_t, UInt64, UInt64)] = []
        func collect(_ pid: pid_t, depth: Int) {
            guard depth < 8 else { return }
            var children = [pid_t](repeating: 0, count: 1024)
            // proc_listchildpids returns a PID count, unlike proc_listpids (bytes).
            let count = children.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, Int32($0.count)) }
            guard count > 0 else { return }
            for child in children.prefix(min(children.count, Int(count))) where child > 0 {
                var info = proc_bsdinfo()
                let size = MemoryLayout<proc_bsdinfo>.size
                guard proc_pidinfo(child, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size,
                      info.pbi_ppid == UInt32(pid) else { continue }
                collect(child, depth: depth + 1)
                descendants.append((child, info.pbi_start_tvsec, info.pbi_start_tvusec))
            }
        }
        collect(parent, depth: 0)
        let children = descendants
        for (pid, _, _) in children { Darwin.kill(pid, SIGTERM) }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            for (pid, seconds, micros) in children {
                var info = proc_bsdinfo()
                let size = MemoryLayout<proc_bsdinfo>.size
                if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size,
                   info.pbi_start_tvsec == seconds, info.pbi_start_tvusec == micros {
                    Darwin.kill(pid, SIGKILL)
                }
            }
            if process.isRunning { Darwin.kill(parent, SIGKILL) }
        }
    }
}
