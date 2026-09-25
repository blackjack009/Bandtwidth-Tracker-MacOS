import Foundation
import Combine
import Darwin

struct InterfaceCounters: Identifiable {
    let id = UUID()
    let name: String
    var received: UInt64
    var sent: UInt64
}

struct Snapshot {
    var perInterface: [String: (rx: UInt64, tx: UInt64)] = [:]
    var totalRx: UInt64 { perInterface.values.reduce(0) { $0 &+ $1.rx } }
    var totalTx: UInt64 { perInterface.values.reduce(0) { $0 &+ $1.tx } }
}

@MainActor
final class BandwidthMonitor: ObservableObject {
    nonisolated init(history: HistoryStore? = nil) {
        self._history = history
    }

    private let _history: HistoryStore?
    var history: HistoryStore? { _history }

    @Published private(set) var downloadSpeed: Double = 0
    @Published private(set) var uploadSpeed: Double = 0
    @Published private(set) var todayDown: UInt64 = 0
    @Published private(set) var todayUp: UInt64 = 0
    @Published private(set) var interfaces: [InterfaceCounters] = []
    @Published private(set) var downloadHistory: [Double] = Array(repeating: 0, count: 60)
    @Published private(set) var uploadHistory: [Double] = Array(repeating: 0, count: 60)

    private var timer: Timer?
    private var lastSampleTime: Date?
    private var lastPerInterface: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var currentDay: String = ""

    private let historyLength = 60

    func start() {
        guard timer == nil else { return }
        currentDay = Self.dayKey(Date())
        // Resume today's accumulator from persisted history (survives restart)
        if let rec = _history?.record(day: currentDay) {
            todayDown = rec.down
            todayUp = rec.up
        }
        tick()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func resetToday() {
        todayDown = 0
        todayUp = 0
        _history?.update(day: currentDay, down: 0, up: 0)
        // Keep lastPerInterface so counting continues from now (no recount of cumulative)
    }

    private func tick() {
        let now = Date()
        let snapshot = Self.readSnapshot().perInterface

        // Midnight rollover (Asia/Jakarta): reset accumulator, keep per-interface baselines
        let day = Self.dayKey(now)
        if day != currentDay {
            currentDay = day
            todayDown = 0
            todayUp = 0
        }

        // Accumulate positive per-interface deltas.
        // Immune to interfaces appearing/disappearing (VPN, AirDrop, USB) — the
        // aggregate-total approach falsely saw a vanished interface as a counter reset.
        var tickDown: UInt64 = 0
        var tickUp: UInt64 = 0
        for (iface, curr) in snapshot {
            if let last = lastPerInterface[iface] {
                // curr < last means that single interface's counter reset (reboot / re-add)
                tickDown &+= curr.rx >= last.rx ? (curr.rx - last.rx) : curr.rx
                tickUp   &+= curr.tx >= last.tx ? (curr.tx - last.tx) : curr.tx
            }
            // First sight of an interface: establish baseline only; do NOT count its
            // cumulative-since-boot bytes into today.
            lastPerInterface[iface] = curr
        }

        todayDown &+= tickDown
        todayUp   &+= tickUp

        _history?.update(day: currentDay, down: todayDown, up: todayUp)

        // Interfaces list (cumulative since boot, for display)
        interfaces = snapshot
            .map { InterfaceCounters(name: $0.key, received: $0.value.rx, sent: $0.value.tx) }
            .sorted { ($0.received + $0.sent) > ($1.received + $1.sent) }

        // Live rate from this tick's delta
        if let prevTime = lastSampleTime {
            let dt = now.timeIntervalSince(prevTime)
            if dt > 0 {
                downloadSpeed = Double(tickDown) / dt
                uploadSpeed   = Double(tickUp) / dt
            }
        }
        lastSampleTime = now

        var dh = downloadHistory
        var uh = uploadHistory
        dh.append(downloadSpeed); if dh.count > historyLength { dh.removeFirst(dh.count - historyLength) }
        uh.append(uploadSpeed);   if uh.count > historyLength { uh.removeFirst(uh.count - historyLength) }
        downloadHistory = dh
        uploadHistory = uh
    }

    private static func dayKey(_ date: Date) -> String {
        HistoryStore.dayKey(date)
    }

    // Reads 64-bit interface byte counters via sysctl(NET_RT_IFLIST2).
    // getifaddrs()'s if_data exposes only 32-bit counters that wrap every 4.29 GB.
    static func readSnapshot() -> Snapshot {
        var result = Snapshot()
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]

        var len = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return result }

        var buffer = [UInt8](repeating: 0, count: len)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            sysctl(&mib, u_int(mib.count), raw.baseAddress, &len, nil, 0) == 0
        }
        guard ok else { return result }

        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            while offset + headerSize <= len {
                let hdr = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr.self).pointee
                let msglen = Int(hdr.ifm_msglen)
                if msglen <= 0 { break }

                if hdr.ifm_type == UInt8(RTM_IFINFO2) {
                    let if2 = base.advanced(by: offset)
                        .assumingMemoryBound(to: if_msghdr2.self).pointee
                    var nameBuf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(if2.ifm_index), &nameBuf) != nil {
                        let name = String(cString: nameBuf)
                        if !name.hasPrefix("lo") {
                            let rx = if2.ifm_data.ifi_ibytes
                            let tx = if2.ifm_data.ifi_obytes
                            if rx > 0 || tx > 0 {
                                result.perInterface[name] = (rx, tx)
                            }
                        }
                    }
                }
                offset += msglen
            }
        }
        return result
    }
}

enum ByteFormat {
    static func speed(_ bytesPerSec: Double) -> String {
        let bps = bytesPerSec * 8
        let units = ["bps", "Kbps", "Mbps", "Gbps"]
        var value = bps
        var i = 0
        while value >= 1000, i < units.count - 1 { value /= 1000; i += 1 }
        return String(format: "%.2f %@", value, units[i])
    }

    static func bytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var i = 0
        while value >= 1024, i < units.count - 1 { value /= 1024; i += 1 }
        return String(format: "%.2f %@", value, units[i])
    }

    static func compactBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var i = 0
        while value >= 1024, i < units.count - 1 { value /= 1024; i += 1 }
        if i <= 1 { return String(format: "%.0f %@", value, units[i]) }
        return String(format: "%.2f %@", value, units[i])
    }

    static func shortBytes(_ bytes: UInt64) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var value = Double(bytes)
        var i = 0
        while value >= 1024, i < units.count - 1 { value /= 1024; i += 1 }
        if bytes == 0 { return "·" }
        if i <= 1 { return String(format: "%.0f%@", value, units[i]) }
        return String(format: "%.1f%@", value, units[i])
    }

    static func compactRate(_ bytesPerSec: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSec
        var i = 0
        while value >= 1024, i < units.count - 1 { value /= 1024; i += 1 }
        if i == 0 { return String(format: "%.0f %@", value, units[i]) }
        return String(format: "%.1f %@", value, units[i])
    }
}
