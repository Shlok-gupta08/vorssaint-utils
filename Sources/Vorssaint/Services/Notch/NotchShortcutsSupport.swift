// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchShortcutSession: Equatable, Identifiable {
    let id: String
    let pid: Int32
    let executable: String
    let started: Date
    var executions: Int

    func elapsed(at date: Date) -> String {
        let seconds = Int(max(0, date.timeIntervalSince(started)))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Only Apple's explicit workflow start/finish messages are accepted. Keeping
/// an app or runner process open is not evidence that a shortcut is running.
enum NotchShortcutsSupport {
    static let predicate = "subsystem == 'com.apple.shortcuts' AND category == 'WorkflowExecution' AND "
        + "(eventMessage BEGINSWITH '-[WFWorkflowController _run]' OR "
        + "eventMessage BEGINSWITH '-[WFWorkflowController setFinishedRunningWithSuccess:]')"
    struct Event {
        let pid: Int32
        let executable: String
        let date: Date
        let started: Bool
        var id: String { "\(pid):\(date.timeIntervalSince1970):\(started)" }
    }

    static func event(_ data: Data, now: Date = Date()) -> Event? {
        guard data.count <= 32 << 10,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["subsystem"] as? String == "com.apple.shortcuts",
              json["category"] as? String == "WorkflowExecution",
              let number = json["processID"] as? NSNumber, number.int64Value > 0, number.int64Value <= Int32.max,
              let executable = json["processImagePath"] as? String, isAppleRunner(executable),
              let message = json["eventMessage"] as? String,
              let stamp = json["timestamp"] as? String else { return nil }
        let began = message.hasPrefix("-[WFWorkflowController _run] Starting workflow execution:")
        let ended = message.hasPrefix("-[WFWorkflowController setFinishedRunningWithSuccess:] Stopping workflow execution:")
        guard began || ended else { return nil }
        let iso = stamp.replacingOccurrences(of: " ", with: "T")
            .replacingOccurrences(of: #"([+-]\d{2})(\d{2})$"#, with: "$1:$2", options: .regularExpression)
        guard let date = AgentTimestamp.parse(iso), date <= now.addingTimeInterval(60) else { return nil }
        return Event(pid: number.int32Value, executable: executable, date: date, started: began)
    }

    static func isAppleRunner(_ path: String) -> Bool {
        if path == "/usr/bin/shortcuts" { return true }
        let name = (path as NSString).lastPathComponent
        return (path.hasPrefix("/System/Applications/Shortcuts.app/") && name == "Shortcuts")
            || (path.hasPrefix("/System/Library/CoreServices/Shortcuts Events.app/") && name == "Shortcuts Events")
            || (path.hasPrefix("/System/Library/PrivateFrameworks/WorkflowKit.framework/")
                && path.contains("/BackgroundShortcutRunner.xpc/") && name == "BackgroundShortcutRunner")
    }
}

struct NotchShortcutsLifecycle {
    private(set) var sessions: [Int32: NotchShortcutSession] = [:]
    private var seen = Set<String>()
    private var orderedSeen: [String] = []

    mutating func apply(_ event: NotchShortcutsSupport.Event) {
        guard seen.insert(event.id).inserted else { return }
        orderedSeen.append(event.id)
        if orderedSeen.count > 8192 {
            for id in orderedSeen.prefix(2048) { seen.remove(id) }
            orderedSeen.removeFirst(2048)
        }
        if event.started {
            if var session = sessions[event.pid], session.executable == event.executable {
                session.executions += 1
                sessions[event.pid] = session
            } else {
                sessions[event.pid] = NotchShortcutSession(id: event.id, pid: event.pid,
                    executable: event.executable, started: event.date, executions: 1)
            }
        } else if var session = sessions[event.pid], event.date >= session.started {
            session.executions -= 1
            sessions[event.pid] = session.executions > 0 ? session : nil
        }
    }

    mutating func prune(isAlive: (NotchShortcutSession) -> Bool) {
        sessions = sessions.filter { isAlive($0.value) }
    }

    var ordered: [NotchShortcutSession] {
        sessions.values.sorted { $0.started == $1.started ? $0.pid < $1.pid : $0.started < $1.started }
    }
}
