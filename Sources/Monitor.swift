import Foundation
import Observation

/// Single source of truth for the menu bar and the panel. Sampled once per second.
@MainActor @Observable
final class Monitor {
    static let historyLength = 60

    private(set) var cpu: CPUSampler.Usage?
    private(set) var cpuHistory: [Double] = []
    private(set) var memory: MemorySampler.Usage?
    private(set) var network: NetworkSampler.Usage?
    private(set) var rxHistory: [Double] = []
    private(set) var txHistory: [Double] = []

    // Only sampled while the panel is open.
    private(set) var processes: [ProcessSampler.Entry] = []
    private(set) var interfaceName: String?

    @ObservationIgnored private var cpuSampler = CPUSampler()
    @ObservationIgnored private var netSampler = NetworkSampler()
    @ObservationIgnored private var procSampler = ProcessSampler()
    @ObservationIgnored private var panelOpen = false

    init() {
        // Prime the delta-based samplers so the first tick has something to compare with.
        _ = cpuSampler.sample()
        _ = netSampler.sample()
        memory = MemorySampler.sample()
    }

    func setPanelOpen(_ open: Bool) {
        guard open != panelOpen else { return }
        panelOpen = open
        procSampler.reset()
        processes = []
        if open {
            interfaceName = NetworkSampler.primaryInterfaceName()
            _ = procSampler.sample(top: 0)
        }
    }

    func tick() {
        if let c = cpuSampler.sample() {
            cpu = c
            Self.append(c.total, to: &cpuHistory)
        }
        memory = MemorySampler.sample() ?? memory
        if let n = netSampler.sample() {
            network = n
            Self.append(n.rxPerSec, to: &rxHistory)
            Self.append(n.txPerSec, to: &txHistory)
        }
        if panelOpen {
            processes = procSampler.sample(top: 5)
        }
    }

    private static func append(_ v: Double, to history: inout [Double]) {
        history.append(v)
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
    }
}
