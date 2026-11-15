// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Darwin

/// Observes lifecycle metadata and exact native titles to retrieve library artwork.
/// Accessibility values that do not match a shortcut name are discarded; no
/// actions, dialog content or results are retained, and no shortcut is launched.
final class NotchShortcutsService: ObservableObject {
    static let shared = NotchShortcutsService()
    @Published private(set) var sessions: [NotchShortcutSession] = []
    var primary: NotchShortcutSession? { sessions.first }
    var executionCount: Int { sessions.reduce(0) { $0 + $1.executions } }
    static let appURL = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")

    // The workflow log supplies lifecycle only, not shortcut artwork. Never
    // invent a colorful tile or reuse artwork from a previous execution.
    @Published private(set) var currentIcon: NSImage? = nil
    @Published private(set) var currentShortcutName: String? = nil

    private let queue = DispatchQueue(label: "com.vorssaint.notch.shortcuts", qos: .utility)
    private var generation = UUID() // main thread
    private var running = false
    private var queueToken: UUID? // queue-owned below
    private var child: Process?
    private var pipe: Pipe?
    private var timer: DispatchSourceTimer?
    private var pending = Data()
    private var lifecycle = NotchShortcutsLifecycle()
    private let metadata = NotchShortcutMetadata()
    private var lastMetadata = Date.distantPast
    private var metadataSessionID: String?

    private init() {}

    func syncWithPreferences() {
        guard NotchSupport.isEnabled(), UserDefaults.standard.bool(forKey: DefaultsKey.notchShortcutsEnabled)
        else { stop(); return }
        guard !running else { return }
        running = true
        let token = UUID(); generation = token
        queue.async { [weak self] in
            guard let self else { return }
            self.queueToken = token
            self.lifecycle = NotchShortcutsLifecycle()
            self.startStream(token: token)
            self.backfill(last: "24h", token: token)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(150))
            timer.setEventHandler { [weak self] in self?.publish(token: token) }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        guard running else { return }
        running = false; generation = UUID(); sessions = []
        currentIcon = nil; currentShortcutName = nil
        queue.async { [weak self] in
            guard let self else { return }
            self.queueToken = nil
            self.timer?.cancel(); self.timer = nil
            self.pipe?.fileHandleForReading.readabilityHandler = nil
            if let child = self.child, child.isRunning { child.terminate() }
            self.child = nil; self.pipe = nil; self.pending = Data()
            self.lifecycle = NotchShortcutsLifecycle()
        }
    }

    func openApp() { NSWorkspace.shared.open(Self.appURL) }

    func canCancel(_ session: NotchShortcutSession) -> Bool {
        session.executable.contains("/BackgroundShortcutRunner.xpc/")
            && (session.executable as NSString).lastPathComponent == "BackgroundShortcutRunner"
    }

    func cancel(_ session: NotchShortcutSession) {
        guard canCancel(session) else { return }
        queue.async { [weak self] in
            guard let self, self.lifecycle.sessions[session.pid]?.id == session.id else { return }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            guard proc_pidinfo(session.pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
                  Double(info.pbi_start_tvsec) <= session.started.timeIntervalSince1970 + 2,
                  proc_pidpath(session.pid, &path, UInt32(path.count)) > 0,
                  String(cString: path) == session.executable else { return }
            // Stop this isolated runner only, never the Shortcuts application.
            kill(session.pid, SIGTERM)
        }
    }

    private func startStream(token: UUID) {
        guard queueToken == token, child == nil else { return }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        // An unexpected parent crash cannot leave an immortal log reader.
        process.arguments = ["stream", "--style", "ndjson", "--level", "info", "--timeout", "5m",
                             "--predicate", NotchShortcutsSupport.predicate]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.queue.async { [weak self] in
                guard let self, self.queueToken == token else { return }
                self.consume(data)
                self.publish(token: token)
            }
        }
        process.terminationHandler = { [weak self] finished in
            self?.queue.async { [weak self] in
                guard let self, self.queueToken == token, self.child === finished else { return }
                output.fileHandleForReading.readabilityHandler = nil
                self.child = nil; self.pipe = nil; self.pending = Data()
                self.queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.queueToken == token else { return }
                    self.startStream(token: token)
                    self.backfill(last: "10s", token: token)
                }
            }
        }
        do { try process.run(); child = process; pipe = output }
        catch {
            output.fileHandleForReading.readabilityHandler = nil
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.startStream(token: token) }
        }
    }

    private func backfill(last: String, token: UUID) {
        let limit = 8 << 20
        let result = BoundedProcessRunner.run("/usr/bin/log", ["show", "--last", last, "--style", "ndjson",
            "--predicate", NotchShortcutsSupport.predicate], timeout: 6, maxOutputBytes: limit)
        guard queueToken == token, result.status == 0, !result.timedOut, result.output.count < limit else { return }
        for line in result.output.split(separator: 10) {
            if let event = NotchShortcutsSupport.event(Data(line)) { lifecycle.apply(event) }
        }
        publish(token: token)
    }

    private func consume(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            if let event = NotchShortcutsSupport.event(line) { lifecycle.apply(event) }
        }
        if pending.count > 32 << 10 { pending = Data() }
    }

    private func publish(token: UUID) {
        guard queueToken == token else { return }
        lifecycle.prune { session in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(session.pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
                  Double(info.pbi_start_tvsec) <= session.started.timeIntervalSince1970 + 2 else { return false }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            return proc_pidpath(session.pid, &path, UInt32(path.count)) > 0 && String(cString: path) == session.executable
        }
        let next = lifecycle.ordered
        var detail: NotchShortcutMetadata.Value?
        let refreshMetadata = !next.isEmpty && (metadataSessionID != next.first?.id || Date().timeIntervalSince(lastMetadata) >= 5)
        if refreshMetadata, let primary = next.first {
            metadataSessionID = primary.id
            lastMetadata = Date()
            detail = metadata.read(pid: primary.pid, now: lastMetadata)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.generation == token else { return }
            if self.sessions.first?.id != next.first?.id {
                self.currentIcon = nil; self.currentShortcutName = nil
            }
            if refreshMetadata {
                self.currentIcon = detail?.icon; self.currentShortcutName = detail?.name
            }
            if self.sessions != next { self.sessions = next }
        }
    }
}
