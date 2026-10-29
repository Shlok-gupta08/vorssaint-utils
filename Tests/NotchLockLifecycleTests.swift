// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI

extension NotchScreenRefreshContract.Scheduler {
    func asyncAfter(deadline: NotchScreenRefreshContract.Deadline, execute: @escaping () -> Void) {
        asyncAfter(deadline: deadline, execute: DispatchWorkItem(block: execute))
    }
}

/// Production scheduling, retirement and reuse against a controlled clock.
/// These checks never lock the Mac or create a system overlay Space.
enum NotchLockLifecycleTests {
    typealias DispatchQueue = NotchScreenRefreshContract.DispatchQueue
    enum NotchLockScreenSupport {
        static var enabled = true
        static let spaceLevel: Int32 = 400
        static func isEnabled() -> Bool { enabled }
    }
    final class NotchOverlaySpace {
        static var creations = 0
        var visible = false
        var closed = false
        var removals = 0
        init?(absoluteLevel: Int32, initiallyVisible: Bool) {
            Self.creations += 1
            visible = initiallyVisible
        }
        func setVisible(_ visible: Bool) { self.visible = visible }
        func close() { closed = true }
        func remove(_ panel: NotchLockScreenPanel) { removals += 1 }
    }
    final class NotchLockScreenPanel {
        var hidden = false
        func orderOut(_ sender: Any?) { hidden = true }
    }
    final class Source {
        static let shared = Source()
        var stops = 0
        func stop() { stops += 1 }
        func pause() { stops += 1 }
    }
    typealias NotchDownloadService = Source
    typealias NotchCalendarService = Source
    typealias NotchMusicService = Source
    typealias AgentUsageService = Source
    struct NotchLockScreenModel {
        struct Gates {}
        var padlockOpen = false
        var islandRetracted = false
        var playedWhileLocked = false
    }
    class State {
        struct Frames {}
        var model = NotchLockScreenModel()
        var scene: [NotchLockScreenPanel] = []
        var island: NotchLockScreenPanel?
        var space: NotchOverlaySpace?
        var cachedSpace: NotchOverlaySpace?
        var preparationWork: DispatchWorkItem?
        var sceneWork: DispatchWorkItem?
        var padlockWork: DispatchWorkItem?
        var playbackSubscription: Bool?
        var screenObserver: NSObjectProtocol?
        var presentationGeneration = 0
        var wasLocked = false
        var isScreenSaver = false
        var shownScenes = 0
        func showScene(in space: NotchOverlaySpace, frames: Frames, gates: NotchLockScreenModel.Gates) {
            shownScenes += 1
            scene = [NotchLockScreenPanel()]
        }
        static func fadeOut(_ panel: NotchLockScreenPanel, after delay: TimeInterval, completion: @escaping () -> Void) {
            let work = DispatchWorkItem { panel.orderOut(nil); completion() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.2, execute: work)
        }
    }

    static func run(_ suite: TestSuite) {
        DispatchQueue.main = NotchScreenRefreshContract.Scheduler()
        NotchLockScreenSupport.enabled = true
        NotchOverlaySpace.creations = 0
        Source.shared.stops = 0
        let service = Service()
        for _ in 0..<10 { service.prepare() }
        suite.expect(DispatchQueue.main.pending == 1 && NotchOverlaySpace.creations == 0,
                     "lock-screen preparation coalesces and waits for the desktop to settle")
        DispatchQueue.main.advance(0.8)
        let prepared = service.cachedSpace
        suite.expect(prepared != nil && prepared?.visible == false && NotchOverlaySpace.creations == 1,
                     "preparation creates one hidden Space without showing lock-screen content")

        service.space = prepared
        service.cachedSpace = nil
        service.scheduleScene(frames: .init(), gates: .init())
        DispatchQueue.main.advance(0.2)
        suite.expect(service.shownScenes == 0, "glass panels and source discovery do not run in the first lock-animation frames")
        service.hide(unlocking: false, stopsSources: false)
        DispatchQueue.main.advance(1)
        suite.expect(service.shownScenes == 0 && service.cachedSpace === prepared && prepared?.closed == false,
                     "a short lock cancels pending panel creation and reuses its Space")

        service.space = prepared
        service.cachedSpace = nil
        service.presentationGeneration += 1
        service.scheduleScene(frames: .init(), gates: .init())
        DispatchQueue.main.advance(0.36)
        suite.expect(service.shownScenes == 1, "a settled lock screen still displays its activity and media panels")
        let island = NotchLockScreenPanel()
        service.island = island
        service.hide(unlocking: true, stopsSources: false)
        let relock = NotchOverlaySpace(absoluteLevel: 400, initiallyVisible: true)!
        service.space = relock
        service.presentationGeneration += 1
        service.model.islandRetracted = false
        DispatchQueue.main.advance(0.7)
        suite.expect(!service.model.islandRetracted && service.space === relock,
                     "an old unlock callback cannot retract a newer lock presentation")
        suite.expect(service.cachedSpace === prepared && prepared?.removals == 2 && Source.shared.stops == 0,
                     "retiring panels leave the reusable Space without stopping sources taken over by the desktop")
        service.hide(unlocking: false, stopsSources: false)
        suite.expect(relock.closed, "the cache retains at most one Space after an interrupted unlock")
        NotchLockScreenSupport.enabled = false
        service.prepare()
        suite.expect(service.cachedSpace == nil && prepared?.closed == true,
                     "disabling the feature releases the cached Space")

        NotchLockScreenSupport.enabled = true
        service.prepare()
        service.close()
        DispatchQueue.main.advance(1)
        suite.expect(service.cachedSpace == nil && DispatchQueue.main.pending == 0,
                     "closing cancels preparation so a disabled or stopped app cannot recreate an overlay")
    }
}
