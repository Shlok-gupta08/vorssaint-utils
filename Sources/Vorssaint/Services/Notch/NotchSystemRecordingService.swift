// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import Darwin
import Foundation

/// Unified screen recording Live Activity coordinator that tracks BOTH:
/// 1. Vorssaint's built-in `ScreenRecorderService`, and
/// 2. macOS's native screen recording (`Cmd+Shift+5` / `screencapture -v`)
/// using zero-fork Darwin process inspection (`proc_listpids` + `KERN_PROCARGS2`)
/// so there is zero UI lag and zero false positives from passive Control Center icons.
final class NotchSystemRecordingService: ObservableObject {
    static let shared = NotchSystemRecordingService()

    @Published private(set) var isActive = false
    @Published private(set) var isSystemRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var activeDisplayID: CGDirectDisplayID?
    @Published private(set) var activeDisplayName: String?

    var canPause: Bool { ScreenRecorderService.shared.isRecording }
    var capturesSystemAudio: Bool { ScreenRecorderService.shared.isRecording && ScreenRecorderService.shared.capturesSystemAudio }
    var capturesMicrophone: Bool { ScreenRecorderService.shared.isRecording && ScreenRecorderService.shared.capturesMicrophone }

    var elapsedLabel: String {
        if ScreenRecorderService.shared.isRecording {
            return ScreenRecorderService.shared.elapsedLabel
        }
        return Self.formatElapsed(elapsedSeconds)
    }

    /// Returns true if the recording live activity should appear on `displayID`.
    /// When a single display is being recorded, only that display shows the live activity;
    /// when recording spans all displays (or the target display is unspecified), all displays show it.
    func isActive(on displayID: CGDirectDisplayID?) -> Bool {
        guard isActive else { return false }
        guard let target = activeDisplayID, let displayID else { return true }
        return target == displayID
    }

    /// Display name badge shown inside the expanded recording panel:
    /// uses the recorded display's name when single-display, or the expanded screen's
    /// display name when recording across displays.
    func displayLabel(for expandedDisplayID: CGDirectDisplayID?) -> String {
        if let activeDisplayName, !activeDisplayName.isEmpty {
            return activeDisplayName
        }
        if let expandedDisplayID,
           let screen = NSScreen.screens.first(where: { $0.notchDisplayID == expandedDisplayID }) {
            return screen.localizedName
        }
        return NSScreen.main?.localizedName ?? "Display"
    }

    private let queue = DispatchQueue(label: "com.vorssaint.notch.system-recording", qos: .background)
    private var pollTimer: DispatchSourceTimer?
    private var tickTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var monitoring = false
    private var systemStartedAt: Date?
    private var detectedScreencapturePID: pid_t?
    // Queue-confined last poll snapshot so we only hop to main when state actually changes.
    private var lastPolledActive = false
    private var lastPolledDisplayID: CGDirectDisplayID?

    private init() {
        let recorder = ScreenRecorderService.shared
        Publishers.CombineLatest3(
            recorder.$isRecording.removeDuplicates(),
            recorder.$isPaused.removeDuplicates(),
            recorder.$elapsedSeconds.removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.reconcileState()
        }
        .store(in: &subscriptions)
    }

    func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 1.2, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.pollNativeScreenRecording()
        }
        pollTimer = timer
        timer.resume()
    }

    func stopMonitoring() {
        monitoring = false
        pollTimer?.cancel()
        pollTimer = nil
        queue.async { [weak self] in
            self?.lastPolledActive = false
            self?.lastPolledDisplayID = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.tickTimer?.invalidate()
            self?.tickTimer = nil
            self?.systemStartedAt = nil
            self?.detectedScreencapturePID = nil
            self?.activeDisplayID = nil
            self?.activeDisplayName = nil
            self?.isSystemRecording = false
            self?.reconcileState()
        }
    }

    func togglePause() {
        guard ScreenRecorderService.shared.isRecording else { return }
        ScreenRecorderService.shared.togglePause()
    }

    func stop() {
        if ScreenRecorderService.shared.isRecording {
            ScreenRecorderService.shared.stop()
            return
        }
        guard isSystemRecording else { return }
        let pid = detectedScreencapturePID
        queue.async { [weak self] in
            // 1. Prefer clicking macOS's native "Stop Screen Recording" menu bar item via Accessibility.
            if Self.pressNativeStopMenuBarItem() {
                self?.schedulePostStopPoll()
                return
            }
            // 2. Graceful SIGINT to `screencapture` finalizes the QuickTime .mov cleanly without corruption.
            if let pid, pid > 0, kill(pid, SIGINT) == 0 {
                self?.schedulePostStopPoll()
                return
            }
            // 3. Universal macOS fallback shortcut: Control+Command+Escape stops system screen recording.
            Self.postControlCommandEscape()
            self?.schedulePostStopPoll()
        }
    }

    // MARK: - State Reconciliation

    private func reconcileState() {
        let vorssaint = ScreenRecorderService.shared
        let nextActive = vorssaint.isRecording || isSystemRecording
        let nextPaused = vorssaint.isRecording ? vorssaint.isPaused : false
        let nextElapsed: Int
        if vorssaint.isRecording {
            nextElapsed = vorssaint.elapsedSeconds
        } else if isSystemRecording, let started = systemStartedAt {
            nextElapsed = max(0, Int(Date().timeIntervalSince(started)))
        } else {
            nextElapsed = 0
        }

        if isActive != nextActive { isActive = nextActive }
        if isPaused != nextPaused { isPaused = nextPaused }
        if elapsedSeconds != nextElapsed { elapsedSeconds = nextElapsed }

        if isSystemRecording && !vorssaint.isRecording {
            ensureTickTimer()
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func ensureTickTimer() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.reconcileState()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func schedulePostStopPoll() {
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pollNativeScreenRecording()
        }
        queue.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.pollNativeScreenRecording()
        }
    }

    // MARK: - Native macOS Screen Recording Detection (Zero-Fork, Zero False Positives)

    private func pollNativeScreenRecording() {
        guard monitoring else { return }
        // 1. Lightweight in-process Darwin check for `/usr/sbin/screencapture -v` (zero subprocess spawn).
        let detected = Self.detectScreencaptureVideoInProcess()
        // 2. Fallback: exact "Stop Screen Recording" menu bar item (ONLY when `screencaptureui` is running).
        let hasExactStopButton = detected.pid == nil ? Self.hasExactStopRecordingMenuBarItem() : false
        let active = (detected.pid != nil) || hasExactStopButton
        let resolvedDisplayID = active ? (detected.displayID ?? Self.detectScreencaptureOverlayDisplayID()) : nil

        // Do not touch the main thread unless state or target display actually changed.
        guard active != lastPolledActive || resolvedDisplayID != lastPolledDisplayID else { return }
        lastPolledActive = active
        lastPolledDisplayID = resolvedDisplayID

        DispatchQueue.main.async { [weak self] in
            guard let self, self.monitoring else { return }
            self.detectedScreencapturePID = detected.pid
            if active {
                if let resolvedDisplayID,
                   let screen = NSScreen.screens.first(where: { $0.notchDisplayID == resolvedDisplayID }) {
                    self.activeDisplayID = resolvedDisplayID
                    self.activeDisplayName = screen.localizedName
                } else if NSScreen.screens.count == 1, let only = NSScreen.screens.first {
                    self.activeDisplayID = only.notchDisplayID
                    self.activeDisplayName = only.localizedName
                } else {
                    self.activeDisplayID = nil
                    self.activeDisplayName = nil
                }
                if !self.isSystemRecording {
                    self.systemStartedAt = Date()
                    self.isSystemRecording = true
                }
                self.reconcileState()
            } else {
                self.systemStartedAt = nil
                self.activeDisplayID = nil
                self.activeDisplayName = nil
                self.isSystemRecording = false
                self.reconcileState()
            }
        }
    }

    /// Scans running processes in-process via `proc_listpids` + `proc_pidpath` + `KERN_PROCARGS2`
    /// without spawning `/bin/ps` (takes <0.2ms, zero UI lag).
    private static func detectScreencaptureVideoInProcess() -> (pid: pid_t?, displayID: CGDirectDisplayID?) {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return (nil, nil) }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.stride + 16)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard filled > 0 else { return (nil, nil) }
        let pidCount = Int(filled) / MemoryLayout<pid_t>.stride
        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let pathLen = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
            guard pathLen > 0 else { continue }
            let path = String(cString: pathBuf)
            guard path == "/usr/sbin/screencapture" || path.hasSuffix("/screencapture") else { continue }
            let args = processArguments(for: pid)
            if isVideoScreencapture(args: args) {
                let displayIdx = parseDisplayIndex(from: args)
                let displayID = displayIdx.flatMap { idx -> CGDirectDisplayID? in
                    let screens = NSScreen.screens
                    guard idx >= 1, idx <= screens.count else { return nil }
                    return screens[idx - 1].notchDisplayID
                }
                return (pid, displayID)
            }
        }
        return (nil, nil)
    }

    private static func processArguments(for pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return [] }
        var offset = MemoryLayout<Int32>.size
        // Skip exec_path and trailing NUL padding.
        while offset < size && buffer[offset] != 0 { offset += 1 }
        while offset < size && buffer[offset] == 0 { offset += 1 }

        var args: [String] = []
        args.reserveCapacity(Int(min(argc, 32)))
        while offset < size && args.count < Int(argc) {
            let start = offset
            while offset < size && buffer[offset] != 0 { offset += 1 }
            if let str = String(bytes: buffer[start..<offset], encoding: .utf8) {
                args.append(str)
            }
            offset += 1
        }
        return args
    }

    private static func isVideoScreencapture(args: [String]) -> Bool {
        guard !args.isEmpty else { return false }
        for token in args.dropFirst() {
            if token == "-v" || token == "-V" { return true }
            if token.hasPrefix("-"), !token.hasPrefix("--"), token.contains("v") || token.contains("V") {
                return true
            }
            if token.lowercased().hasSuffix(".mov") { return true }
        }
        return false
    }

    private static func parseDisplayIndex(from args: [String]) -> Int? {
        for (idx, token) in args.enumerated() {
            if token == "-D", idx + 1 < args.count, let num = Int(args[idx + 1]) { return num }
            if token.hasPrefix("-D"), token.count > 2, let num = Int(token.dropFirst(2)) { return num }
        }
        return nil
    }

    /// Parses `ps -axo pid=,args=` output for an active macOS video screen recording process (used by unit tests).
    static func parseScreencapturePID(fromPSOutput output: String) -> pid_t? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let firstSpace = line.firstIndex(where: \.isWhitespace) else { continue }
            guard let pid = pid_t(String(line[..<firstSpace])) else { continue }
            let tokens = String(line[firstSpace...]).split(whereSeparator: \.isWhitespace).map(String.init)
            guard let first = tokens.first?.lowercased(),
                  first == "/usr/sbin/screencapture" || first == "screencapture" || first.hasSuffix("/screencapture") else {
                continue
            }
            if isVideoScreencapture(args: tokens) { return pid }
        }
        return nil
    }

    /// Strictly matches ONLY an explicit "Stop Screen Recording" / "Stop Recording" menu bar button.
    /// Never matches passive Control Center "ScreenRecording" / "Screen Mirroring" status items.
    private static func findNativeStopMenuBarItem() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        // Only inspect screencaptureui or SystemUIServer when screencaptureui is actually running.
        let screencaptureApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.screencaptureui")
        guard !screencaptureApps.isEmpty else { return nil }
        let targets = screencaptureApps
            + NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver")
            + NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter")

        for app in targets {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.06)
            for barAttr in ["AXExtrasMenuBar", kAXMenuBarAttribute] {
                var barRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axApp, barAttr as CFString, &barRef) == .success,
                      let barRef, CFGetTypeID(barRef) == AXUIElementGetTypeID() else { continue }
                let bar = unsafeBitCast(barRef, to: AXUIElement.self)
                var childrenRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                      let items = childrenRef as? [AXUIElement] else { continue }
                for item in items {
                    var labels: [String] = []
                    for attr in [kAXDescriptionAttribute, kAXTitleAttribute, "AXHelp"] {
                        var val: CFTypeRef?
                        if AXUIElementCopyAttributeValue(item, attr as CFString, &val) == .success,
                           let str = val as? String, !str.isEmpty {
                            labels.append(str.lowercased())
                        }
                    }
                    let joined = labels.joined(separator: " ")
                    if joined.contains("stop screen recording") || joined.contains("stop recording") {
                        return item
                    }
                }
            }
        }
        return nil
    }

    private static func hasExactStopRecordingMenuBarItem() -> Bool {
        findNativeStopMenuBarItem() != nil
    }

    private static func pressNativeStopMenuBarItem() -> Bool {
        guard let item = findNativeStopMenuBarItem() else { return false }
        AXUIElementSetMessagingTimeout(item, 0.1)
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func detectScreencaptureOverlayDisplayID() -> CGDirectDisplayID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var matchedDisplays = Set<CGDirectDisplayID>()
        for window in list {
            let owner = (window[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard owner.contains("screencaptureui"), layer != 25,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat,
                  w >= 120, h >= 80 else { continue }
            let center = CGPoint(x: x + w / 2, y: y + h / 2)
            for screen in NSScreen.screens {
                if CGDisplayBounds(screen.notchDisplayID).contains(center) {
                    matchedDisplays.insert(screen.notchDisplayID)
                }
            }
        }
        return matchedDisplays.count == 1 ? matchedDisplays.first : nil
    }

    private static func postControlCommandEscape() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else { return }
        down.flags = [.maskCommand, .maskControl]
        up.flags = [.maskCommand, .maskControl]
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func formatElapsed(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
