// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit.pwr_mgt

/// Runs the production assertion lifecycle against inert power-service doubles.
enum DictationSleepPreventionTests {
    static var assertions = Set<IOPMAssertionID>()
    static var nextID: IOPMAssertionID = 1
    static var renewals = 0
    @discardableResult static func IOPMAssertionCreateWithName(_ type: CFString, _ level: IOPMAssertionLevel,
                                           _ reason: CFString, _ id: UnsafeMutablePointer<IOPMAssertionID>) -> IOReturn {
        id.pointee = nextID; nextID += 1; assertions.insert(id.pointee)
        return kIOReturnSuccess
    }
    @discardableResult static func IOPMAssertionRelease(_ id: IOPMAssertionID) -> IOReturn {
        assertions.remove(id); return kIOReturnSuccess
    }
    @discardableResult static func IOPMAssertionDeclareUserActivity(_ reason: CFString, _ type: IOPMUserActiveType,
                                                _ id: UnsafeMutablePointer<IOPMAssertionID>) -> IOReturn {
        if id.pointee != 0 { assertions.remove(id.pointee); renewals += 1 }
        // The real API may rotate the id when renewing: callers must keep it.
        id.pointee = nextID; nextID += 1; assertions.insert(id.pointee)
        return kIOReturnSuccess
    }
    enum ProcessInfo {
        static let processInfo = Activity()
        final class Activity {
            var systemUptime = 100.0
            var active = 0
            func beginActivity(options: Foundation.ProcessInfo.ActivityOptions, reason: String) -> NSObjectProtocol {
                active += 1; return NSObject()
            }
            func endActivity(_ activity: NSObjectProtocol) { active -= 1 }
        }
    }
    class Fixture {
        var phase = DictationPhase.idle
        var isEnabled = true
        var sleepActivity: NSObjectProtocol?
        var displayAssertion = IOPMAssertionID(0)
        var systemAssertion = IOPMAssertionID(0)
        var userActivityAssertion = IOPMAssertionID(0)
        var hasDisplayAssertion = false
        var hasSystemAssertion = false
        var lastActivityDeclaration = 0.0
    }
    static func run(_ suite: TestSuite) {
        defer { assertions = []; nextID = 1; renewals = 0; ProcessInfo.processInfo.active = 0 }
        let host = Host()
        host.phase = .recording; host.syncSleepPrevention()
        suite.expect(assertions.count == 3 && ProcessInfo.processInfo.active == 1,
                     "dictation acquires display, system and user-activity assertions")
        host.phase = .processing; host.syncSleepPrevention()
        suite.expect(assertions.count == 3 && renewals == 1 && ProcessInfo.processInfo.active == 1,
                     "processing reuses dictation's existing assertions without leaking activity tokens")
        ProcessInfo.processInfo.systemUptime += 6
        host.declareUserActivityIfNeeded()
        suite.expect(assertions.count == 3 && renewals == 2, "speech renews one user-activity assertion even when its id rotates")
        host.declareUserActivityIfNeeded()
        suite.expect(renewals == 2, "speech activity updates are rate limited")
        host.phase = .completed; host.syncSleepPrevention()
        suite.expect(assertions.isEmpty && ProcessInfo.processInfo.active == 0,
                     "completion releases every dictation assertion and activity token")
        for phase in [DictationPhase.idle, .failed] {
            host.phase = .recording; host.syncSleepPrevention()
            host.phase = phase; host.syncSleepPrevention(); host.releaseSleepPrevention()
            suite.expect(assertions.isEmpty && ProcessInfo.processInfo.active == 0,
                         "cancellation and failure release dictation sleep prevention idempotently")
        }
    }
}
