// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI

/// Renders production settings and exercises click targets in owned fixtures.
/// No desktop input, permission requests, or user preference edits are used.
enum NotchSettingsProbe {
    static func runAndExit() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let directory = URL(fileURLWithPath: "build/settings-review", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { print("SETTINGS PROBE FAILED: \(error)"); exit(1) }
        var failures: [String] = []
        checkNavigationHitTargets(failures: &failures)
        var count = 0
        let cases = NotchSettingsTab.allCases.map { ($0, "") } + [(NotchSettingsTab.overview, "hover")]
        for width: CGFloat in [540, 900, 1440, 2048] {
            for (section, query) in cases {
                autoreleasepool {
                    let size = CGSize(width: width, height: 900)
                    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                                          styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.alphaValue = 0.01
                    window.sharingType = .none
                    window.appearance = NSAppearance(named: .darkAqua)
                    let root = NotchSettings(section: section, query: query)
                        .environment(\.colorScheme, .dark)
                        .frame(width: width, height: size.height)
                        .background(Color(nsColor: .windowBackgroundColor))
                    let view = NSHostingView(rootView: root)
                    view.frame = CGRect(origin: .zero, size: size)
                    window.contentView = view
                    window.orderFrontRegardless()
                    view.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
                    view.layoutSubtreeIfNeeded()
                    let label = "\(Int(width))-\(query.isEmpty ? String(describing: section) : "search")"
                    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                        failures.append("\(label): no rendered surface")
                        window.orderOut(nil)
                        return
                    }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    do {
                        guard let png = bitmap.representation(using: .png, properties: [:]) else {
                            failures.append("\(label): no PNG"); window.orderOut(nil); return
                        }
                        try png.write(to: directory.appendingPathComponent(label + ".png"))
                        count += 1
                    } catch { failures.append("\(label): \(error)") }
                    func check(_ child: NSView) {
                        if child is NSControl, !child.isHiddenOrHasHiddenAncestor {
                            let rect = child.convert(child.bounds, to: view)
                            if rect.intersects(view.bounds), rect.minX < -1 || rect.maxX > width + 1 {
                                failures.append("\(label): control exceeds the horizontal reading area")
                            }
                        }
                        child.subviews.forEach(check)
                    }
                    check(view)
                    window.orderOut(nil)
                }
            }
        }
        print(failures.isEmpty ? "SETTINGS PROBE OK: \(count) native renders in \(directory.path)" : "SETTINGS PROBE FAILED\n" + failures.joined(separator: "\n"))
        exit(failures.isEmpty ? 0 : 1)
    }
    private static func checkNavigationHitTargets(failures: inout [String]) {
        var activations = 0
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 38),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01
        window.sharingType = .none
        let host = NSHostingView(rootView: NotchSettingsNavigationButton(title: "Design", symbol: "display", selected: false) { activations += 1 }
            .frame(width: 280, height: 38))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        for (index, point) in [NSPoint(x: 270, y: 19), NSPoint(x: 6, y: 6), NSPoint(x: 140, y: 32)].enumerated() {
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: index * 2, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
                                        windowNumber: window.windowNumber, context: nil, eventNumber: index * 2 + 1, clickCount: 1, pressure: 0)!
            // Dispatch only to this fixture's window; no system event injection.
            NSApplication.shared.postEvent(up, atStart: false)
            window.sendEvent(down)
            window.sendEvent(up)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if activations != index + 1 { failures.append("navigation padding click \(index) did not activate exactly once") }
        }
        window.orderOut(nil)
        print("SETTINGS HIT TARGETS: \(activations)/3 padding clicks activated")
    }

}
#endif
