// MenuStats — a tiny, offline menu bar monitor for CPU, RAM and network.
// No network access, no helpers, no daemons: it only reads kernel counters.

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor = Monitor()
    private let popover = NSPopover()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingController(rootView: PanelView(monitor: monitor))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.imagePosition = .imageOnly
        }
        renderMenuBar()

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.monitor.tick()
                self?.renderMenuBar()
            }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func renderMenuBar() {
        statusItem.button?.image = MenuBarRenderer.image(.init(
            cpuHistory: monitor.cpuHistory,
            cpu: monitor.cpu?.total,
            memory: monitor.memory?.fraction,
            rx: monitor.network?.rxPerSec,
            tx: monitor.network?.txPerSec))
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverWillShow(_ notification: Notification) { monitor.setPanelOpen(true) }
    func popoverDidClose(_ notification: Notification) { monitor.setPanelOpen(false) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
