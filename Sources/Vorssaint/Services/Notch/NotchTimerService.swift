// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Session state is intentionally memory-only: a settings restore or relaunch
/// must never resurrect a timer from a different day or another Mac.
final class NotchTimerService: ObservableObject {
    static let shared = NotchTimerService()
    @Published private(set) var session = NotchTimerSession()
    @Published var showsSeconds = false
    private let origin = ContinuousClock.now
    private var completionTask: Task<Void, Never>?
    private var suspended = true
    private var completionNeedsPresentation = false
    private let alert = NotchTimerAlert()
    private init() {}

    var now: TimeInterval {
        let parts = origin.duration(to: .now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    func syncWithPreferences() {
        guard NotchTimerSupport.isEnabled() else { stop(); return }
        suspended = false
        finishIfDue(at: now)
        presentCompletionIfPossible()
        if session.completed { alert.start(enabled: NotchTimerSupport.isSoundEnabled()) }
        scheduleCompletion()
    }

    func start(mode: NotchTimerMode, minutes: Int, seconds: Int = 0) {
        guard !suspended, NotchTimerSupport.isEnabled() else { return }
        guard !session.hasSession else { return }
        alert.stop()
        session.start(mode: mode, minutes: minutes, seconds: seconds, now: now, configuration: .load())
        scheduleCompletion()
    }

    func pauseOrResume() {
        guard !suspended, NotchTimerSupport.isEnabled() else { return }
        let instant = now
        finishIfDue(at: instant)
        if session.isRunning { session.pause(at: instant) }
        else if session.isPaused { session.resume(at: instant) }
        scheduleCompletion()
    }

    func startNext() {
        guard !suspended, NotchTimerSupport.isEnabled() else { return }
        guard session.canStartNext else { return }
        alert.stop()
        completionNeedsPresentation = false
        session.startNext(at: now)
        scheduleCompletion()
    }

    func cancel() {
        alert.stop()
        completionNeedsPresentation = false
        completionTask?.cancel(); completionTask = nil
        session.cancel()
    }

    func suspend() {
        suspended = true
        alert.suspend()
        completionTask?.cancel(); completionTask = nil
    }

    func stop() { suspend(); cancel() }

    private func finishIfDue(at instant: TimeInterval) {
        guard session.finishIfDue(at: instant) else { return }
        alert.stop()
        alert.start(enabled: NotchTimerSupport.isSoundEnabled())
        completionNeedsPresentation = true
        presentCompletionIfPossible()
    }

    private func presentCompletionIfPossible() {
        let notch = NotchService.shared
        guard completionNeedsPresentation, notch.acceptsUserInteraction else { return }
        completionNeedsPresentation = false
        let text = FeatureStrings.notchActivities(L10n.shared.language)
        notch.presentTimerCompletion(NotchNotice(event: .timer,
            title: session.cycleFinished ? text.pomodoroFinished : text.finished,
            detail: text.phase(session.phase), symbol: "timer"))
    }

    private func scheduleCompletion() {
        completionTask?.cancel(); completionTask = nil
        guard !suspended, let deadline = session.deadline else { return }
        let remaining = max(0, deadline - now)
        completionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(remaining), clock: .continuous) }
            catch { return }
            guard let self, !Task.isCancelled, !self.suspended, NotchTimerSupport.isEnabled() else { return }
            self.completionTask = nil
            self.finishIfDue(at: self.now)
        }
    }
}
