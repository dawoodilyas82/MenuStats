// Samplers read kernel counters directly. No network access, no helpers, no permissions.

import AppKit
import Darwin
import SystemConfiguration

/// CPU usage from cumulative tick counters (delta between two samples).
struct CPUSampler {
    private var last: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    struct Usage { var user: Double; var system: Double; var total: Double }

    mutating func sample() -> Usage? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let now = (user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                   idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
        defer { last = now }
        guard let prev = last else { return nil }

        let user = Double(now.user &- prev.user) + Double(now.nice &- prev.nice)
        let system = Double(now.system &- prev.system)
        let idle = Double(now.idle &- prev.idle)
        let all = user + system + idle
        guard all > 0 else { return nil }
        return Usage(user: user / all, system: system / all, total: (user + system) / all)
    }
}

/// Memory usage computed the same way Activity Monitor reports "Memory Used".
enum MemorySampler {
    struct Usage {
        var app: UInt64; var wired: UInt64; var compressed: UInt64; var total: UInt64
        var used: UInt64 { app + wired + compressed }
        var fraction: Double { Double(used) / Double(total) }
    }

    static func sample() -> Usage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let page = UInt64(vm_kernel_page_size)
        return Usage(app: (UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)) * page,
                     wired: UInt64(stats.wire_count) * page,
                     compressed: UInt64(stats.compressor_page_count) * page,
                     total: ProcessInfo.processInfo.physicalMemory)
    }
}

/// Network throughput from 64-bit interface byte counters (physical interfaces only,
/// so VPN tunnels don't double-count traffic).
struct NetworkSampler {
    private var last: (rx: UInt64, tx: UInt64, time: TimeInterval)?

    struct Usage { var rxPerSec: Double; var txPerSec: Double; var rxTotal: UInt64; var txTotal: UInt64 }

    private static func isPhysical(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    private static func counters() -> (rx: UInt64, tx: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 else { return nil }

        var rx: UInt64 = 0, tx: UInt64 = 0
        var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                defer { offset += Int(hdr.ifm_msglen) }
                guard hdr.ifm_msglen > 0 else { offset = len; return }
                guard Int32(hdr.ifm_type) == RTM_IFINFO2 else { continue }

                let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard msg.ifm_flags & IFF_UP != 0, msg.ifm_flags & IFF_LOOPBACK == 0,
                      if_indextoname(UInt32(msg.ifm_index), &nameBuf) != nil,
                      isPhysical(String(cString: nameBuf)) else { continue }
                rx &+= msg.ifm_data.ifi_ibytes
                tx &+= msg.ifm_data.ifi_obytes
            }
        }
        return (rx, tx)
    }

    mutating func sample() -> Usage? {
        guard let now = Self.counters() else { return nil }
        let t = ProcessInfo.processInfo.systemUptime
        defer { last = (now.rx, now.tx, t) }
        guard let prev = last, t > prev.time else { return nil }
        let dt = t - prev.time
        // Counters can go backwards when an interface disappears; treat that as zero.
        let drx = now.rx >= prev.rx ? now.rx - prev.rx : 0
        let dtx = now.tx >= prev.tx ? now.tx - prev.tx : 0
        return Usage(rxPerSec: Double(drx) / dt, txPerSec: Double(dtx) / dt, rxTotal: now.rx, txTotal: now.tx)
    }

    /// Display name of the interface carrying the default route, e.g. "Wi-Fi".
    static func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "MenuStats" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let bsd = global["PrimaryInterface"] as? String else { return nil }
        let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let match = all.first { SCNetworkInterfaceGetBSDName($0) as String? == bsd }
        return match.flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? } ?? bsd
    }
}

/// Per-process CPU usage for the current user's processes (others aren't readable
/// without root, which this app deliberately doesn't have).
struct ProcessSampler {
    struct Entry: Identifiable {
        let id: pid_t
        let name: String
        let appPath: String?   // enclosing .app bundle, used for the icon
        let cpu: Double        // fraction of one core, like Activity Monitor's "% CPU"
    }

    private var last: [pid_t: UInt64] = [:]
    private var lastTime: UInt64 = 0

    mutating func reset() { last = [:]; lastTime = 0 }

    mutating func sample(top n: Int) -> [Entry] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let found = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        let now = mach_absolute_time()

        var current: [pid_t: UInt64] = [:]
        var deltas: [(pid: pid_t, ticks: UInt64)] = []
        for pid in pids.prefix(max(found, 0)) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let t = info.pti_total_user + info.pti_total_system
            current[pid] = t
            if let prev = last[pid], t > prev { deltas.append((pid, t - prev)) }
        }
        defer { last = current; lastTime = now }
        guard lastTime > 0, now > lastTime else { return [] }

        // Task times and mach_absolute_time share units on both Intel and Apple Silicon.
        let wall = Double(now - lastTime)
        return deltas.sorted { $0.ticks > $1.ticks }.prefix(n).map { d in
            let path = Self.path(of: d.pid)
            return Entry(id: d.pid,
                         name: path.map { ($0 as NSString).lastPathComponent } ?? "pid \(d.pid)",
                         appPath: path.flatMap(Self.appBundle),
                         cpu: Double(d.ticks) / wall)
        }
    }

    private static func path(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
    }

    private static func appBundle(_ path: String) -> String? {
        guard let r = path.range(of: ".app/") else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }
}
