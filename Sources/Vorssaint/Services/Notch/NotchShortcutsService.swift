// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Darwin

/// Observes lifecycle logs without launching Shortcuts or querying its library.
final class NotchShortcutsService: ObservableObject {
    static let shared = NotchShortcutsService()
    @Published private(set) var sessions: [NotchShortcutSession] = []
    var primary: NotchShortcutSession? { sessions.first }
    var executionCount: Int { sessions.reduce(0) { $0 + $1.executions } }
    static let appURL = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")

    let icon = NSWorkspace.shared.icon(forFile: NotchShortcutsService.appURL.path)

    private let queue = DispatchQueue(label: "com.vorssaint.notch.shortcuts", qos: .utility)
    private var generation = UUID() // main thread
    private var running = false
    private var queueToken: UUID? // queue-owned below
    private var child: Process?
    private var pipe: Pipe?
    private var timer: DispatchSourceTimer?
    private var pending = Data()
    private var lifecycle = NotchShortcutsLifecycle()
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
            // Do not resurrect historical starts from retained runner processes.
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
            // XPC's SIGTERM handler may defer exit until its workflow finishes.
            // The user explicitly stops this isolated runner; do not signal the
            // Shortcuts UI or a shared foreground process.
            let result = kill(session.pid, SIGKILL)
            NSLog("Shortcut stop: pid=%d result=%d errno=%d", session.pid, result, result == 0 ? 0 : errno)
            self.publish(token: self.queueToken ?? UUID())
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
        let next = lifecycle.ordered.map { session -> NotchShortcutSession in
            var enriched = session
            if enriched.identity == nil {
                enriched.identity = NotchShortcutIdentityResolver.resolve(pid: session.pid, executable: session.executable)
            }
            return enriched
        }
        for enriched in next where enriched.identity != nil {
            lifecycle.attachIdentity(enriched.identity, for: enriched.pid)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.generation == token else { return }
            if self.sessions != next { self.sessions = next }
        }
    }
}
