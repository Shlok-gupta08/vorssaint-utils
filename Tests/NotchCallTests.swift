// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchCallTests {
    static func run(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var state = NotchCallLifecycle()
        func observation(_ phase: NotchCallPhase, muted: Bool = false) -> NotchCallLifecycle.Observation {
            .init(pid: 42, bundleID: "com.apple.FaceTime", appName: "FaceTime", phase: phase,
                  muted: muted, canAnswer: phase == .ringing, canEnd: true, canMute: phase == .active)
        }
        state.update([observation(.ringing)], running: [42], at: now)
        let identity = state.sessions.first?.id
        suite.expect(state.sessions.first?.phase == .ringing && state.sessions.first?.connectedAt == nil,
                     "ringing calls never count unanswered ringing time as conversation time")
        state.update([observation(.active)], running: [42], at: now.addingTimeInterval(5))
        suite.expect(state.sessions.first?.id == identity
                     && state.sessions.first?.elapsed(at: now.addingTimeInterval(66)) == "1:01",
                     "answering preserves call identity and starts the connected clock")
        state.update([observation(.held, muted: true)], running: [42], at: now.addingTimeInterval(10))
        suite.expect(state.sessions.first?.muted == true && state.sessions.first?.connectedAt == now.addingTimeInterval(5),
                     "hold and mute do not restart the call timer")
        state.update([], running: [42], at: now.addingTimeInterval(11))
        suite.expect(state.sessions.first?.id == identity && state.sessions.first?.canEnd == false,
                     "brief UI redraws retain the timer but disable stale actions")
        state.update([observation(.active)], running: [42], at: now.addingTimeInterval(12))
        suite.expect(state.sessions.first?.id == identity && state.sessions.first?.canEnd == true,
                     "recovered call controls keep the same session")
        state.update([], running: [42], at: now.addingTimeInterval(15))
        suite.expect(state.sessions.isEmpty, "an ended call clears after a bounded redraw grace period")
        state.update([observation(.active)], running: [42], at: now.addingTimeInterval(20))
        suite.expect(state.sessions.first?.id != identity, "a later call gets a fresh identity and clock")
        state.update([], running: [], at: now.addingTimeInterval(20.1))
        suite.expect(state.sessions.isEmpty, "quitting a calling app clears its activity immediately")
        state.update([observation(.active)], running: [42], at: now.addingTimeInterval(30))
        let previousCall = state.sessions.first?.id
        state.update([observation(.ringing)], running: [42], at: now.addingTimeInterval(31))
        suite.expect(state.sessions.first?.id != previousCall && state.sessions.first?.connectedAt == nil,
                     "a new incoming call cannot inherit an earlier call's clock or actionable identity")

        let candidates: [NotchCompactActivity] = [.music, .timer, .agents, .call, .calendar]
        suite.expect(NotchPillActivityLayout.ordered(candidates, preferred: .agents,
                     context: .init(musicPlaying: true, calendarImminent: true)).first == .call,
                     "an ongoing call outranks manual primary choices, meetings and music")
        suite.expect(NotchSupport.compactActivities(timer: true, downloads: false, agents: true,
                     calendar: false, music: true, call: true).first == .call,
                     "the hardware notch also gives calls first priority")

        suite.expect(NotchCallSupport.phase(labels: ["Mute"], windowTitle: "Microphone test", canAnswer: false, canEnd: false) == nil,
                     "a recording, microphone test, or meeting preview is not a call")
        suite.expect(NotchCallSupport.phase(labels: ["Decline"], windowTitle: "Invitation", canAnswer: false, canEnd: true) == nil,
                     "a non-call decline button alone never creates a call")
        suite.expect(NotchCallSupport.phase(labels: ["Leave"], windowTitle: "Project channel", canAnswer: false, canEnd: true) == nil,
                     "leaving a chat channel cannot be mistaken for ending a call")
        suite.expect(NotchCallSupport.phase(labels: ["Answer", "Decline"], windowTitle: "FaceTime", canAnswer: true, canEnd: true) == .ringing,
                     "a verified answer/decline pair represents an incoming call")
        suite.expect(NotchCallSupport.phase(labels: ["End call", "Resume call"], windowTitle: "FaceTime", canAnswer: false, canEnd: true) == .held,
                     "resume controls identify a held call")
        suite.expect(NotchCallSupport.phase(labels: ["Cancel call"], windowTitle: "Calling Alex", canAnswer: false, canEnd: true) == .connecting,
                     "outgoing calls stay connecting until the UI reports an active call")
        suite.expect(NotchCallSupport.action(for: "endCallButton") == .end
                     && NotchCallSupport.action(for: "Unmute microphone") == .mute,
                     "stable accessibility identifiers and mute labels map to call-specific controls")
        suite.expect(NotchCallSupport.action(for: "Mute notifications") == nil
                     && NotchCallSupport.action(for: "End meeting for all") == nil,
                     "call controls never target notification mute or conference-wide termination")
        suite.expect(NotchCallSupport.browserCallWindow("Google Meet — Planning")
                     && !NotchCallSupport.browserCallWindow("Video recording studio"),
                     "browser scanning is limited to recognized meeting windows")
    }
}
