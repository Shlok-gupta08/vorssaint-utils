// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine

/// Reads call controls, never audio or conversation contents. AX work is
/// bounded and serialized off the UI thread; late reads cannot revive a call.
final class NotchCallService: ObservableObject {
    static let shared = NotchCallService()
    @Published private(set) var sessions: [NotchCallSession] = []
    var primary: NotchCallSession? { sessions.first }
    private let queue = DispatchQueue(label: "com.vorssaint.notch.calls", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var generation = UUID()
    private var lifecycle = NotchCallLifecycle() // queue-owned
    private var running = false

    private init() {}

    func syncWithPreferences() {
        guard NotchCallSupport.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.notchCallsEnabled) else { stop(); return }
        guard !running else { return }
        running = true
        let token = UUID(); generation = token
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(150))
        source.setEventHandler { [weak self] in self?.read(generation: token) }
        timer = source
        source.resume()
    }

    func stop() {
        running = false; generation = UUID()
        timer?.cancel(); timer = nil
        sessions = []
        queue.async { [weak self] in self?.lifecycle = NotchCallLifecycle() }
    }

    func open(_ session: NotchCallSession) {
        NSRunningApplication(processIdentifier: session.pid)?.activate(options: [.activateAllWindows])
    }

    func perform(_ action: NotchCallSupport.Action, session: NotchCallSession) {
        guard sessions.contains(where: { $0.id == session.id }) else { return }
        queue.async { [weak self] in
            guard let self, AXIsProcessTrusted(),
                  let app = NSRunningApplication(processIdentifier: session.pid),
                  app.bundleIdentifier == session.bundleID,
                  let scan = self.scan(app), let button = scan.buttons[action] else { return }
            // Re-scan on the click: stale buttons from a previous call are
            // never pressed, and no keyboard shortcuts are sent globally.
            guard self.lifecycle.sessions.contains(where: { $0.id == session.id }) else { return }
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    private func read(generation token: UUID) {
        let apps = NSWorkspace.shared.runningApplications
        let running = Set(apps.map(\.processIdentifier))
        var observations: [NotchCallLifecycle.Observation] = []
        if AXIsProcessTrusted() {
            for app in apps {
                guard let bundle = app.bundleIdentifier,
                      NotchCallSupport.appBundleIDs.contains(bundle) || NotchCallSupport.browsers.contains(bundle) else { continue }
                if let result = scan(app) { observations.append(result.observation) }
            }
        }
        lifecycle.update(observations, running: running, at: Date())
        let value = lifecycle.sessions
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.generation == token else { return }
            if self.sessions != value { self.sessions = value }
        }
    }

    private struct Scan {
        let observation: NotchCallLifecycle.Observation
        let buttons: [NotchCallSupport.Action: AXUIElement]
    }

    private func scan(_ app: NSRunningApplication) -> Scan? {
        guard let bundle = app.bundleIdentifier else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.06)
        let windows = elements(root, kAXWindowsAttribute)
        let deadline = Date().addingTimeInterval(0.25)
        for window in windows.prefix(10) {
            guard Date() < deadline else { break }
            let title = string(window, kAXTitleAttribute)
            if NotchCallSupport.browsers.contains(bundle) && !NotchCallSupport.browserCallWindow(title) { continue }
            var pending = [window]
            var buttons: [NotchCallSupport.Action: AXUIElement] = [:]
            var labels: [String] = []
            var visited = 0
            while visited < pending.count, visited < 400, Date() < deadline {
                let element = pending[visited]
                visited += 1
                let role = string(element, kAXRoleAttribute)
                if role == kAXStaticTextRole {
                    let value = NotchCallSupport.normalized(string(element, kAXValueAttribute))
                    if ["calling", "connecting", "on hold"].contains(value) { labels.append(value) }
                }
                if role == kAXButtonRole || role == kAXCheckBoxRole || role == kAXMenuButtonRole {
                    let candidates = [string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute),
                                      string(element, kAXHelpAttribute), string(element, kAXIdentifierAttribute)]
                    for label in candidates where !label.isEmpty {
                        labels.append(NotchCallSupport.normalized(label))
                        if let action = NotchCallSupport.action(for: label), enabled(element) { buttons[action] = element }
                    }
                }
                pending.append(contentsOf: elements(element, kAXChildrenAttribute).prefix(60))
            }
            // A mute button, microphone stream, or meeting preview alone is
            // not a call. A call-specific end/answer control is required.
            guard buttons[.end] != nil else { continue }
            let incoming = buttons[.answer] != nil
            guard let phase = NotchCallSupport.phase(labels: labels, windowTitle: title,
                                                     canAnswer: incoming, canEnd: buttons[.end] != nil) else { continue }
            let muted = labels.contains { $0 == "unmute" || $0.hasPrefix("unmute ") }
            return Scan(observation: .init(pid: app.processIdentifier, bundleID: bundle,
                                           appName: app.localizedName ?? "Call", phase: phase, muted: muted,
                                           canAnswer: incoming, canEnd: true, canMute: buttons[.mute] != nil), buttons: buttons)
        }
        return nil
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
    private func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
    private func enabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success else { return true }
        return value as? Bool ?? true
    }

#if VORSSAINT_DEVELOPMENT
    /// The native probe supplies its own harmless call-control window; no
    /// external application is activated and no call action is performed.
    func readApplicationForProbe(_ app: NSRunningApplication, completion: @escaping (NotchCallLifecycle.Observation?) -> Void) {
        queue.async { [weak self] in
            let observation = self?.scan(app)?.observation
            DispatchQueue.main.async { completion(observation) }
        }
    }
#endif
}
