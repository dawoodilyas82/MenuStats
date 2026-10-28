# MenuStats

A small, offline macOS menu bar monitor for CPU, memory and network.

- **Menu bar:** CPU sparkline, RAM bar, upload/download speeds, colour-coded by load
  (green < 50%, amber 50–80%, red > 80%).
- **Panel (click):** Liquid Glass cards with 60 s CPU and network history, a memory
  breakdown, and the top 5 processes by CPU.

It only reads kernel counters: no network access, no helper tools, no root, no
permission prompts. Requires macOS 26 or later (for Liquid Glass).

## Build

```bash
./build.sh            # builds build/MenuStats.app
./build.sh install    # also copies it to ~/Applications and launches it
```

Needs the Xcode command line tools (`swiftc`). The app is ad-hoc signed.
Turn on "Open at login" from the panel.

## Layout

| File | Purpose |
| --- | --- |
| `Sources/Samplers.swift` | Reads CPU, memory, network and per-process counters |
| `Sources/Monitor.swift` | Samples once a second and keeps 60 s of history |
| `Sources/MenuBarRenderer.swift` | Draws the menu bar image |
| `Sources/PanelView.swift` | SwiftUI Liquid Glass panel |
| `Sources/Format.swift` | Number formatting and colours |
| `Sources/main.swift` | App entry point, status item and popover |

Note: the process list shows only your own processes; system processes need root to read.
