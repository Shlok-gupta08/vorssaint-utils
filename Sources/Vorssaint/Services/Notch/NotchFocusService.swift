// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import Foundation

/// Monitors macOS Focus / Do Not Disturb state transitions and takes over the
/// native macOS Focus On/Off notification banner at the system level so only
/// Vorssaint's iOS-style Dynamic Island Focus pill appears.
final class NotchFocusService: ObservableObject {
    static let shared = NotchFocusService()

    @Published private(set) var currentFocus: NotchFocusState = .off
    let stateChanged = PassthroughSubject<NotchFocusState, Never>()

    private let queue = DispatchQueue(label: "com.vorssaint.notch.focus", qos: .utility)
    private var running = false
    private var generation = UUID()
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var dbPollTimer: DispatchSourceTimer?
    private var logChild: Process?
    private var logPipe: Pipe?
    private var logPending = Data()
    private var knownModes: [String: (name: String, symbol: String, tint: String)] = [:]
    private var hasInitialBaseline = false
    private var lastEmitted: (state: NotchFocusState, date: Date)?
    private var lastAssertionsMTime: Date?

    // Native Focus toast/banner takeover via Accessibility on ControlCenter (macOS 27 pill),
    // NotificationCenter, and OSDUIHelper.
    private var axObservers: [pid_t: (observer: AXObserver, app: AXUIElement, bundleID: String)] = [:]
    private var hiddenNativeWindows: [(element: AXUIElement, originalOrigin: CGPoint)] = []
    private var bannerScanWork: DispatchWorkItem?

    private init() {}

    func syncWithPreferences() {
        guard NotchFocusSupport.isEnabled() else { stop(); return }
        if !running {
            start()
        } else {
            syncBannerTakeover()
        }
    }

    private func start() {
        running = true
        let token = UUID()
        generation = token
        hasInitialBaseline = false

        let dnc = DistributedNotificationCenter.default()
        let names: [Notification.Name] = [
            Notification.Name("_NSDoNotDisturbEnabledNotification"),
            Notification.Name("_NSDoNotDisturbDisabledNotification"),
            Notification.Name("com.apple.donotdisturb.state.changed"),
            Notification.Name("com.apple.focus.state.changed"),
        ]
        for name in names {
            let obs = dnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.handleDistributedNotification(note)
            }
            distributedObservers.append(obs)
        }

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.syncBannerTakeover()
            })
        }

        syncBannerTakeover()

        queue.async { [weak self] in
            guard let self else { return }
            self.pollDatabase(emitIfChanged: false, token: token)
            self.hasInitialBaseline = true
            self.startLogStream(token: token)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1.5, repeating: 1.5, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in
                self?.pollDatabase(emitIfChanged: true, token: token)
            }
            self.dbPollTimer = timer
            timer.resume()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        generation = UUID()
        let dnc = DistributedNotificationCenter.default()
        distributedObservers.forEach(dnc.removeObserver)
        distributedObservers.removeAll()
        let ws = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(ws.removeObserver)
        workspaceObservers.removeAll()
        detachBannerTakeover()
        queue.async { [weak self] in
            guard let self else { return }
            self.dbPollTimer?.cancel(); self.dbPollTimer = nil
            self.logPipe?.fileHandleForReading.readabilityHandler = nil
            if let child = self.logChild, child.isRunning { child.terminate() }
            self.logChild = nil; self.logPipe = nil; self.logPending = Data()
            self.lastAssertionsMTime = nil
        }
    }

    /// Used by NotchNotificationService to avoid mirroring a Focus banner twice.
    func isFocusNotification(_ content: NotchNotificationContent) -> Bool {
        guard NotchFocusSupport.isEnabled() else { return false }
        let fields = [content.app, content.title, content.subtitle, content.body].filter { !$0.isEmpty }
        return NotchFocusSupport.parseBannerStrings(fields, knownModes: knownModes) != nil
    }

    // MARK: - Distributed Notifications

    private func handleDistributedNotification(_ notification: Notification) {
        guard running else { return }
        let name = notification.name.rawValue
        let token = generation
        if name == "_NSDoNotDisturbEnabledNotification" {
            queue.async { [weak self] in
                guard let self else { return }
                let state = self.readDatabaseState() ?? NotchFocusState(
                    isActive: true, identifier: "com.apple.donotdisturb.mode.default",
                    name: "Do Not Disturb", symbol: "moon.fill", tintName: "indigo")
                self.deliver(state, token: token)
            }
        } else if name == "_NSDoNotDisturbDisabledNotification" {
            let offState = NotchFocusState(
                isActive: false,
                identifier: currentFocus.identifier,
                name: currentFocus.name == "Focus" ? "Do Not Disturb" : currentFocus.name,
                symbol: currentFocus.symbol,
                tintName: currentFocus.tintName
            )
            deliver(offState, token: token)
        } else {
            queue.async { [weak self] in
                self?.pollDatabase(emitIfChanged: true, token: token)
            }
        }
    }

    // MARK: - DoNotDisturb DB Polling (exact mode name, icon, tint)

    private func readDatabaseState() -> NotchFocusState? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/DoNotDisturb/DB", directoryHint: .isDirectory)
        let assertionsURL = dir.appending(path: "Assertions.json")
        let modesURL = dir.appending(path: "ModeConfigurations.json")
        let assertionsData = try? Data(contentsOf: assertionsURL)
        let modesData = try? Data(contentsOf: modesURL)
        guard assertionsData != nil || modesData != nil else { return nil }
        let parsed = NotchFocusSupport.parseDatabase(assertionsData: assertionsData, modesData: modesData)
        if !parsed.modes.isEmpty {
            knownModes = parsed.modes
        }
        return parsed.active
    }

    private func pollDatabase(emitIfChanged: Bool, token: UUID) {
        let assertionsURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/DoNotDisturb/DB/Assertions.json")
        let mtime = (try? assertionsURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if emitIfChanged, let mtime, mtime == lastAssertionsMTime { return }
        if let mtime { lastAssertionsMTime = mtime }

        let assertionsData = try? Data(contentsOf: assertionsURL)
        guard assertionsData != nil else { return }
        let modesURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/DoNotDisturb/DB/ModeConfigurations.json")
        let modesData = try? Data(contentsOf: modesURL)
        let parsed = NotchFocusSupport.parseDatabase(assertionsData: assertionsData, modesData: modesData)
        if !parsed.modes.isEmpty { knownModes = parsed.modes }

        let nextState: NotchFocusState
        if let active = parsed.active {
            nextState = active
        } else {
            nextState = NotchFocusState(
                isActive: false,
                identifier: currentFocus.identifier,
                name: currentFocus.name == "Focus" ? "Do Not Disturb" : currentFocus.name,
                symbol: currentFocus.symbol,
                tintName: currentFocus.tintName
            )
        }

        if emitIfChanged {
            deliver(nextState, token: token)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, self.generation == token else { return }
                self.currentFocus = nextState
            }
        }
    }

    // MARK: - Unified Log Stream (zero-permission Focus transition fallback)

    private func startLogStream(token: UUID) {
        guard logChild == nil else { return }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream", "--style", "ndjson", "--level", "info", "--timeout", "5m",
            "--predicate", NotchFocusSupport.logPredicate
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.consumeLog(data, token: token)
            }
        }
        process.terminationHandler = { [weak self] finished in
            self?.queue.async { [weak self] in
                guard let self, self.logChild === finished else { return }
                output.fileHandleForReading.readabilityHandler = nil
                self.logChild = nil; self.logPipe = nil; self.logPending = Data()
                self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.running else { return }
                    self.startLogStream(token: token)
                }
            }
        }
        do {
            try process.run()
            logChild = process
            logPipe = output
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func consumeLog(_ data: Data, token: UUID) {
        logPending.append(data)
        while let newline = logPending.firstIndex(of: 10) {
            let line = Data(logPending[..<newline])
            logPending.removeSubrange(...newline)
            guard let parsed = NotchFocusSupport.parseLogEvent(line) else { continue }
            if let dbState = readDatabaseState(), parsed.isActive {
                deliver(dbState, token: token)
            } else {
                let id = parsed.modeIdentifier ?? currentFocus.identifier
                let meta = knownModes[id] ?? NotchFocusSupport.metadata(for: id)
                let state = NotchFocusState(isActive: parsed.isActive, identifier: id,
                                            name: meta.name, symbol: meta.symbol, tintName: meta.tint)
                deliver(state, token: token)
            }
        }
        if logPending.count > 32 << 10 { logPending = Data() }
    }

    // MARK: - Native macOS Focus Notification Takeover (AX)

    private static let focusToastBundleIDs = [
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.OSDUIHelper",
    ]

    private func syncBannerTakeover() {
        guard running, NotchFocusSupport.hidesNativeBanner(), Permissions.shared.accessibility else {
            detachBannerTakeover()
            return
        }
        var activeTargets: [pid_t: String] = [:]
        for bundleID in Self.focusToastBundleIDs {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                activeTargets[app.processIdentifier] = bundleID
            }
        }
        // Detach any terminated targets.
        for pid in Array(axObservers.keys) where activeTargets[pid] == nil {
            detachObserver(for: pid)
        }
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let service = Unmanaged<NotchFocusService>.fromOpaque(context).takeUnretainedValue()
            service.scheduleBannerIntercept()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for (pid, bundleID) in activeTargets where axObservers[pid] == nil {
            var created: AXObserver?
            guard AXObserverCreate(pid, callback, &created) == .success, let created else { continue }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.08)
            for name in [kAXWindowCreatedNotification, kAXLayoutChangedNotification, kAXCreatedNotification,
                         kAXValueChangedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(created, app, name as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            axObservers[pid] = (created, app, bundleID)
        }
    }

    private func detachObserver(for pid: pid_t) {
        guard let entry = axObservers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(entry.observer), .commonModes)
        for name in [kAXWindowCreatedNotification, kAXLayoutChangedNotification, kAXCreatedNotification,
                     kAXValueChangedNotification, kAXTitleChangedNotification] {
            AXObserverRemoveNotification(entry.observer, entry.app, name as CFString)
        }
    }

    private func detachBannerTakeover() {
        bannerScanWork?.cancel(); bannerScanWork = nil
        restoreHiddenNativeWindows()
        for pid in Array(axObservers.keys) {
            detachObserver(for: pid)
        }
    }

    private func scheduleBannerIntercept() {
        guard running, NotchFocusSupport.hidesNativeBanner() else { return }
        bannerScanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scanAndSuppressNativeFocusBanners()
        }
        bannerScanWork = work
        // Immediate pass + short follow-ups catch macOS 27's persistent NotificationCenter window
        // both before and right after its slide-in placement.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015, execute: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.scanAndSuppressNativeFocusBanners()
        }
    }

    /// Runs a rapid suppression burst when a Focus transition is detected via DB/log/DNC
    /// so the native macOS banner is closed/moved offscreen the instant NotificationCenter spawns it.
    private func scheduleFocusTransitionSuppressionBurst() {
        guard running, NotchFocusSupport.hidesNativeBanner() else { return }
        for delay in [0.0, 0.04, 0.10, 0.20, 0.35, 0.55, 0.80, 1.10] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.scanAndSuppressNativeFocusBanners()
            }
        }
    }

    private static let nativeCloseTitle: String = {
        let bundle = Bundle(path: "/System/Library/CoreServices/NotificationCenter.app")
        return bundle?.localizedString(forKey: "Close", value: "Close", table: "Localizable") ?? "Close"
    }()

    private func scanAndSuppressNativeFocusBanners() {
        guard running, NotchFocusSupport.hidesNativeBanner(), Permissions.shared.accessibility else { return }
        var targets: [(app: AXUIElement, bundleID: String)] = axObservers.values.map { ($0.app, $0.bundleID) }
        if targets.isEmpty {
            for bundleID in Self.focusToastBundleIDs {
                for runningApp in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                    let axApp = AXUIElementCreateApplication(runningApp.processIdentifier)
                    AXUIElementSetMessagingTimeout(axApp, 0.1)
                    targets.append((axApp, bundleID))
                }
            }
        }
        guard !targets.isEmpty else { return }
        let token = generation
        let modes = knownModes
        queue.async { [weak self] in
            for target in targets {
                var windowsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(target.app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                      let windows = windowsRef as? [AXUIElement] else { continue }

                for window in windows {
                    // For ControlCenter, only ever touch compact toast/HUD pills (e.g. macOS 27's
                    // "Do Not Disturb / On" frosted pill), never the full Control Center dropdown.
                    if target.bundleID == "com.apple.controlcenter",
                       let size = Self.windowSize(window),
                       (size.width > 420 || size.height > 140) {
                        continue
                    }

                    // 1. Find individual AXNotificationCenterBanner / Alert cards (depth up to 10).
                    var bannerRoots: [AXUIElement] = []
                    Self.findBannerCards(in: window, depth: 0, into: &bannerRoots)

                    var matchedAnyCard = false
                    for card in bannerRoots {
                        var strings: [String] = []
                        Self.collectLabels(from: card, depth: 0, maxDepth: 8, into: &strings)
                        guard let focusState = NotchFocusSupport.parseBannerStrings(strings, knownModes: modes) else { continue }
                        matchedAnyCard = true
                        Self.dismissBanner(card: card, window: window)
                        self?.deliver(focusState, token: token)
                    }

                    // 2. Fallback: ControlCenter Focus pill, OSDUIHelper HUD, or non-standard toast window.
                    if !matchedAnyCard {
                        var strings: [String] = []
                        Self.collectLabels(from: window, depth: 0, maxDepth: 10, into: &strings)
                        guard let focusState = NotchFocusSupport.parseBannerStrings(strings, knownModes: modes) else { continue }
                        Self.dismissBanner(card: window, window: window)
                        self?.deliver(focusState, token: token)
                    }
                }
            }
        }
    }

    private static func windowSize(_ window: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(sizeRef, to: AXValue.self), .cgSize, &size) else { return nil }
        return size
    }

    private static func findBannerCards(in element: AXUIElement, depth: Int, into roots: inout [AXUIElement]) {
        guard depth <= 10, roots.count < 16 else { return }
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String,
           NotchNotificationSupport.bannerRoles.contains(subrole) || NotchNotificationSupport.stackRoles.contains(subrole) {
            roots.append(element)
            return
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children.prefix(32) {
            findBannerCards(in: child, depth: depth + 1, into: &roots)
        }
    }

    private static func collectLabels(from element: AXUIElement, depth: Int, maxDepth: Int, into result: inout [String]) {
        guard depth <= maxDepth, result.count < 24 else { return }
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, "AXAttributedDescription", "AXHelp"] {
            var val: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &val) == .success, let val {
                let text: String?
                if let str = val as? String {
                    text = str
                } else if let attributed = val as? NSAttributedString {
                    text = attributed.string
                } else {
                    text = nil
                }
                if let text, !text.isEmpty, text.count <= 120, !result.contains(text) {
                    result.append(text)
                }
            }
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children.prefix(24) {
            collectLabels(from: child, depth: depth + 1, maxDepth: maxDepth, into: &result)
        }
    }

    private static func dismissBanner(card: AXUIElement, window: AXUIElement) {
        AXUIElementSetMessagingTimeout(card, 0.1)
        AXUIElementSetMessagingTimeout(window, 0.1)

        // 1. Move window offscreen and collapse size where supported.
        var offscreen = CGPoint(x: -10_000, y: -10_000)
        if let value = AXValueCreate(.cgPoint, &offscreen) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
        var zeroSize = CGSize.zero
        if let sizeVal = AXValueCreate(.cgSize, &zeroSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }

        // 2. Perform NotificationCenter's localized custom Close action or Cancel/Dismiss
        // directly on the banner card / ControlCenter HUD window.
        for target in [card, window] {
            var actionsRef: CFArray?
            if AXUIElementCopyActionNames(target, &actionsRef) == .success,
               let actions = actionsRef as? [String] {
                if let exactClose = NotchNotificationSupport.closeAction(in: actions, title: nativeCloseTitle) {
                    if AXUIElementPerformAction(target, exactClose as CFString) == .success { return }
                }
                if let closeAction = actions.first(where: {
                    $0.localizedCaseInsensitiveContains("close")
                        || $0.localizedCaseInsensitiveContains("dismiss")
                        || $0 == kAXCancelAction
                }) {
                    if AXUIElementPerformAction(target, closeAction as CFString) == .success { return }
                }
            }
        }

        // 3. Fallback: press any Close AXButton descendant inside the banner card.
        _ = pressCloseButton(in: card, depth: 0)
    }

    private static func pressCloseButton(in element: AXUIElement, depth: Int) -> Bool {
        guard depth <= 6 else { return false }
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String, role == kAXButtonRole {
            var subroleRef: CFTypeRef?
            let subrole = (AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success)
                ? (subroleRef as? String ?? "") : ""
            var descRef: CFTypeRef?
            let desc = (AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success)
                ? (descRef as? String ?? "") : ""
            var titleRef: CFTypeRef?
            let title = (AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success)
                ? (titleRef as? String ?? "") : ""
            if subrole == kAXCloseButtonSubrole
                || desc.localizedCaseInsensitiveContains(nativeCloseTitle)
                || desc.localizedCaseInsensitiveContains("close")
                || title.localizedCaseInsensitiveContains(nativeCloseTitle)
                || title.localizedCaseInsensitiveContains("close") {
                return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
            }
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return false }
        for child in children.prefix(24) {
            if pressCloseButton(in: child, depth: depth + 1) { return true }
        }
        return false
    }

    private func restoreHiddenNativeWindows() {
        for entry in hiddenNativeWindows {
            var point = entry.originalOrigin
            if let value = AXValueCreate(.cgPoint, &point) {
                AXUIElementSetAttributeValue(entry.element, kAXPositionAttribute as CFString, value)
            }
        }
        hiddenNativeWindows.removeAll()
    }

    // MARK: - Delivery

    private func deliver(_ next: NotchFocusState, token: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.generation == token else { return }
            let now = Date()
            if let last = self.lastEmitted,
               last.state.isActive == next.isActive && last.state.name == next.name,
               now.timeIntervalSince(last.date) < 1.8 {
                return
            }
            guard self.hasInitialBaseline || next.isActive != self.currentFocus.isActive else { return }
            self.currentFocus = next
            self.lastEmitted = (next, now)
            self.scheduleFocusTransitionSuppressionBurst()
            self.stateChanged.send(next)
        }
    }
}
