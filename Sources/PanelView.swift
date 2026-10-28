import AppKit
import ServiceManagement
import SwiftUI

/// The Liquid Glass panel shown when the menu bar item is clicked.
struct PanelView: View {
    let monitor: Monitor

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                CPUCard(monitor: monitor)
                MemoryCard(memory: monitor.memory)
                NetworkCard(monitor: monitor)
                ProcessesCard(processes: monitor.processes)
                ActionBar()
            }
            .padding(12)
        }
        .frame(width: 320)
    }
}

// MARK: - Cards

private struct Card<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(value).fontWeight(.semibold).monospacedDigit()
            }
            .font(.system(size: 12))
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct CPUCard: View {
    let monitor: Monitor

    var body: some View {
        let total = monitor.cpu?.total ?? 0
        let color = Color(nsColor: Palette.load(total))
        Card(title: "CPU", value: monitor.cpu.map { Fmt.pct($0.total) } ?? "–") {
            HistoryGraph(series: [(monitor.cpuHistory, color)], maxValue: 1, filled: true)
                .frame(height: 44)
            Caption(monitor.cpu.map { "user \(Fmt.pct($0.user)) · system \(Fmt.pct($0.system)) · last 60 s" } ?? "Measuring…")
        }
    }
}

private struct MemoryCard: View {
    let memory: MemorySampler.Usage?

    var body: some View {
        Card(title: "Memory", value: memory.map { "\(Fmt.bytes($0.used)) of \(Fmt.bytes($0.total))" } ?? "–") {
            if let m = memory {
                let parts: [(UInt64, NSColor)] = [(m.app, Palette.memApp), (m.wired, Palette.memWired),
                                                  (m.compressed, Palette.memCompressed)]
                GeometryReader { geo in
                    HStack(spacing: 1.5) {
                        ForEach(parts.indices, id: \.self) { i in
                            Rectangle()
                                .fill(Color(nsColor: parts[i].1))
                                .frame(width: max(0, geo.size.width * CGFloat(parts[i].0) / CGFloat(m.total) - 1.5))
                        }
                        Spacer(minLength: 0)
                    }
                    .background(.quaternary)
                    .clipShape(.capsule)
                }
                .frame(height: 8)
                HStack(alignment: .top) {
                    Legend("App", Fmt.bytes(m.app), Palette.memApp)
                    Spacer()
                    Legend("Wired", Fmt.bytes(m.wired), Palette.memWired)
                    Spacer()
                    Legend("Compressed", Fmt.bytes(m.compressed), Palette.memCompressed)
                }
            }
        }
    }
}

private struct NetworkCard: View {
    let monitor: Monitor

    var body: some View {
        let peak = max(monitor.rxHistory.max() ?? 0, monitor.txHistory.max() ?? 0, 1024)
        Card(title: "Network", value: monitor.interfaceName ?? "") {
            HStack(spacing: 14) {
                Rate(arrow: "arrow.down", value: monitor.network?.rxPerSec, color: Palette.download)
                Rate(arrow: "arrow.up", value: monitor.network?.txPerSec, color: Palette.upload)
            }
            HistoryGraph(series: [(monitor.rxHistory, Color(nsColor: Palette.download)),
                                  (monitor.txHistory, Color(nsColor: Palette.upload))],
                         maxValue: peak, filled: false)
                .frame(height: 36)
            Caption("peak \(Fmt.speed(peak)) · since boot ↓ \(monitor.network.map { Fmt.bytes($0.rxTotal) } ?? "–")  ↑ \(monitor.network.map { Fmt.bytes($0.txTotal) } ?? "–")")
        }
    }
}

private struct ProcessesCard: View {
    let processes: [ProcessSampler.Entry]

    var body: some View {
        Card(title: "Top processes", value: "% CPU") {
            if processes.isEmpty {
                Caption("Measuring…")
            } else {
                VStack(spacing: 6) {
                    ForEach(processes) { p in
                        HStack(spacing: 8) {
                            ProcessIcon(appPath: p.appPath)
                            Text(p.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(String(format: "%.1f", p.cpu * 100))
                                .monospacedDigit()
                                .foregroundStyle(Color(nsColor: Palette.load(p.cpu)))
                        }
                        .font(.system(size: 12))
                    }
                }
            }
        }
    }
}

private struct ActionBar: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    toggleLogin()
                } label: {
                    Label("Open at login", systemImage: launchAtLogin ? "checkmark.circle.fill" : "circle")
                }
                Button("Activity Monitor") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                Spacer(minLength: 0)
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            if let loginError { Caption(loginError) }
        }
    }

    private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't change open at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Small pieces

/// Line graph of the last `Monitor.historyLength` samples, growing in from the right.
private struct HistoryGraph: View {
    let series: [([Double], Color)]
    let maxValue: Double
    let filled: Bool

    var body: some View {
        Canvas { ctx, size in
            for (values, color) in series where values.count > 1 {
                let step = size.width / CGFloat(Monitor.historyLength - 1)
                let start = size.width - step * CGFloat(values.count - 1)
                var line = Path()
                for (i, v) in values.enumerated() {
                    let y = size.height * (1 - CGFloat(min(max(v / maxValue, 0), 1)))
                    let p = CGPoint(x: start + step * CGFloat(i), y: y)
                    i == 0 ? line.move(to: p) : line.addLine(to: p)
                }
                if filled {
                    var area = line
                    area.addLine(to: CGPoint(x: size.width, y: size.height))
                    area.addLine(to: CGPoint(x: start, y: size.height))
                    area.closeSubpath()
                    ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0.05)]),
                                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                }
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .animation(.smooth, value: series.first?.0.count)
    }
}

private struct Rate: View {
    let arrow: String
    let value: Double?
    let color: NSColor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: arrow).foregroundStyle(Color(nsColor: color))
            Text(value.map(Fmt.speed) ?? "–").monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold))
    }
}

private struct Legend: View {
    let name: String
    let value: String
    let color: NSColor
    init(_ name: String, _ value: String, _ color: NSColor) { self.name = name; self.value = value; self.color = color }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(Color(nsColor: color)).frame(width: 6, height: 6)
                Text(name).foregroundStyle(.secondary)
            }
            Text(value).monospacedDigit().padding(.leading, 10)
        }
        .font(.system(size: 10.5))
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
    }
}

private struct ProcessIcon: View {
    let appPath: String?

    var body: some View {
        Group {
            if let appPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                    .resizable()
            } else {
                Image(systemName: "gearshape").resizable().scaledToFit().padding(2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
    }
}
