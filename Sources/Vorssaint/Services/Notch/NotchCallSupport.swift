// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchCallPhase: String, Equatable {
    case ringing, connecting, active, held

    var title: String {
        switch self {
        case .ringing: return "Incoming call"
        case .connecting: return "Calling…"
        case .active: return "Call in progress"
        case .held: return "On hold"
        }
    }
}

struct NotchCallSession: Equatable, Identifiable {
    let id: UUID
    let pid: Int32
    let bundleID: String
    let appName: String
    var phase: NotchCallPhase
    let firstSeen: Date
    var connectedAt: Date?
    var muted: Bool
    var canAnswer: Bool
    var canEnd: Bool
    var canMute: Bool

    func elapsed(at now: Date) -> String {
        guard let connectedAt else { return phase.title }
        let seconds = max(0, Int(now.timeIntervalSince(connectedAt)))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Pure lifecycle rules. Brief AX redraws do not end a call or reset its clock.
struct NotchCallLifecycle {
    struct Observation {
        let pid: Int32
        let bundleID: String
        let appName: String
        let phase: NotchCallPhase
        var muted = false
        var canAnswer = false
        var canEnd = false
        var canMute = false
    }

    private(set) var sessions: [NotchCallSession] = []
    private var lastSeen: [Int32: Date] = [:]

    mutating func update(_ observations: [Observation], running: Set<Int32>, at now: Date) {
        var next: [NotchCallSession] = []
        for observation in observations {
            let existing = sessions.first { $0.pid == observation.pid && $0.bundleID == observation.bundleID }
            let beginsAnotherCall = (observation.phase == .ringing || observation.phase == .connecting)
                && (existing?.phase == .active || existing?.phase == .held)
            var session = (beginsAnotherCall ? nil : existing)
                ?? NotchCallSession(id: UUID(), pid: observation.pid, bundleID: observation.bundleID,
                                    appName: observation.appName, phase: observation.phase, firstSeen: now,
                                    muted: false, canAnswer: false, canEnd: false, canMute: false)
            if session.connectedAt == nil && (observation.phase == .active || observation.phase == .held) {
                session.connectedAt = now
            }
            session.phase = observation.phase
            session.muted = observation.muted
            session.canAnswer = observation.canAnswer
            session.canEnd = observation.canEnd
            session.canMute = observation.canMute
            lastSeen[observation.pid] = now
            next.append(session)
        }
        for old in sessions where !next.contains(where: { $0.pid == old.pid }) && running.contains(old.pid) {
            if let seen = lastSeen[old.pid], now.timeIntervalSince(seen) < 2.5 {
                var retained = old
                // Never keep actionable buttons from an AX tree that vanished.
                retained.canAnswer = false; retained.canEnd = false; retained.canMute = false
                next.append(retained)
            }
        }
        sessions = next.sorted {
            let a = $0.phase == .active || $0.phase == .held
            let b = $1.phase == .active || $1.phase == .held
            if a != b { return a }
            return $0.firstSeen < $1.firstSeen
        }
        lastSeen = lastSeen.filter { key, _ in next.contains { $0.pid == key } }
    }
}

enum NotchCallSupport {
    /// Parked while macOS owns the persistent calling presentation. Keeping
    /// this gate separate from preferences makes a future revival explicit.
    static let isAvailable = false
    enum Action: Hashable { case answer, end, mute }

    static let appBundleIDs: Set<String> = [
        "com.apple.FaceTime", "com.apple.mobilephone", "us.zoom.xos", "com.microsoft.teams2",
        "com.microsoft.teams", "com.cisco.webexmeetingsapp", "com.webex.meetingmanager",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.skype.skype", "net.whatsapp.WhatsApp",
        "org.whispersystems.signal-desktop", "com.facebook.archon", "ru.keepcoder.Telegram"
    ]
    static let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox", "company.thebrowser.Browser"]

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func action(for label: String) -> Action? {
        let text = normalized(label)
        if ["notifications", "participants", "mute all", "for all", "everyone", "channel"].contains(where: { text.contains($0) }) { return nil }
        if text == "end" || text == "leave" { return .end }
        if ["end call", "endcall", "hang up", "hangup", "leave call", "leave meeting", "disconnect call", "decline", "decline call", "end meeting", "cancel call"].contains(where: { text == $0 || text.hasPrefix($0 + " ") }) { return .end }
        if ["answer", "answer call", "accept", "accept call", "accept audio call", "accept video call"].contains(text) { return .answer }
        if ["mute", "unmute", "mute microphone", "unmute microphone", "mute my audio", "unmute my audio"].contains(where: { text == $0 || text.hasPrefix($0 + " ") }) { return .mute }
        return nil
    }

    static func browserCallWindow(_ title: String) -> Bool {
        let text = normalized(title)
        return ["google meet", "meet google", "microsoft teams", "zoom meeting", "webex", "discord"].contains { text.contains($0) }
    }

    static func phase(labels: [String], windowTitle: String, canAnswer: Bool, canEnd: Bool) -> NotchCallPhase? {
        guard canEnd else { return nil }
        let normalizedLabels = labels.map(normalized)
        guard canAnswer || normalizedLabels.contains(where: { action(for: $0) == .end && !$0.hasPrefix("decline") }) else { return nil }
        let strongEnd = normalizedLabels.contains { action(for: $0) == .end && !["end", "leave"].contains($0) }
        let title = normalized(windowTitle)
        let callContext = ["call", "meeting", "facetime", "zoom", "phone"].contains { title.contains($0) }
            || (normalizedLabels.contains(where: { action(for: $0) == .mute })
                && normalizedLabels.contains(where: { $0.contains("video") || $0.contains("camera") }))
        if canAnswer {
            return callContext || normalizedLabels.contains(where: { $0 == "answer" || ($0.contains("call") && action(for: $0) == .answer) }) ? .ringing : nil
        }
        guard strongEnd || callContext else { return nil }
        if normalizedLabels.contains(where: { $0 == "on hold" || $0.contains("resume call") || $0.contains("unhold") }) { return .held }
        if title.hasPrefix("calling ") || title.hasPrefix("connecting ") || normalizedLabels.contains("cancel call")
            || normalizedLabels.contains("calling") || normalizedLabels.contains("connecting") { return .connecting }
        return .active
    }
}
