// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum CombinedFeaturesTests {
    static func run(_ suite: TestSuite) {
        // MARK: 1. Screen Recording Live Activity Priority
        suite.expect(NotchCompactActivity.recording.pillPriority == NotchCompactActivity.timer.pillPriority,
                     "screen recording live activity shares exact pill priority with timer")
        let recActivities = NotchSupport.compactActivities(
            timer: false, recording: true, downloads: false, agents: false, calendar: false, music: false)
        suite.expect(recActivities == [.recording],
                     "compactActivities surfaces active screen recording live activity")

        // MARK: 2. Shelf Drop Live Activity & Modifier Key Inversion
        let playingOrder = NotchPillActivityLayout.ordered(
            [.agents, .shelf, .music], preferred: nil, context: .init(musicPlaying: true))
        suite.expect(playingOrder == [.music, .shelf, .agents],
                     "shelf live activity ranks just below playing music and above AI agents")
        let pausedOrder = NotchPillActivityLayout.ordered(
            [.agents, .shelf, .music], preferred: nil, context: .init(musicPlaying: false))
        suite.expect(pausedOrder.first == .shelf && pausedOrder[1] == .agents,
                     "when music is not playing, shelf live activity takes priority over AI agents")
        suite.expect(NotchCompactActivity.shelf.module == .files,
                     "hovering/opening shelf live activity expands the Shelf module directly")
        suite.expect(ShelfLiveActivitySupport.defaultDuration == 15
                     && ShelfLiveActivitySupport.sanitizedDuration(0) == 0
                     && ShelfLiveActivitySupport.sanitizedDuration(14) == 15
                     && ShelfLiveActivitySupport.sanitizedDuration(32) == 30
                     && ShelfLiveActivitySupport.sanitizedDuration(46) == 45
                     && ShelfLiveActivitySupport.sanitizedDuration(99) == 60,
                     "shelf live activity timer sanitizes cleanly to 0/15/30/45/60s steps")

        suite.expect(ShelfInteractionSupport.effectiveMovesOutside(removeAfterDrop: true, dragIncludesPinned: false, invertPressed: false) == true,
                     "default move mode moves unpinned items")
        suite.expect(ShelfInteractionSupport.effectiveMovesOutside(removeAfterDrop: true, dragIncludesPinned: false, invertPressed: true) == false,
                     "holding invert modifier turns move-by-default into copy")
        suite.expect(ShelfInteractionSupport.effectiveMovesOutside(removeAfterDrop: false, dragIncludesPinned: false, invertPressed: false) == false,
                     "default copy mode copies items")
        suite.expect(ShelfInteractionSupport.effectiveMovesOutside(removeAfterDrop: false, dragIncludesPinned: false, invertPressed: true) == true,
                     "holding invert modifier turns copy-by-default into move")
        suite.expect(ShelfInteractionSupport.effectiveMovesOutside(removeAfterDrop: false, dragIncludesPinned: true, invertPressed: true) == false,
                     "pinned shelf items always copy even with invert modifier")
        suite.expect(ShelfInteractionSupport.outsideDragOperationMask(removeAfterDrop: true, dragIncludesPinned: false, invertPressed: true) == .copy
                     && ShelfInteractionSupport.outsideDragOperationMask(removeAfterDrop: false, dragIncludesPinned: false, invertPressed: true) == .move,
                     "outside drag operation mask locks strictly to the inverted operation when modifier is held")

        // MARK: 3. Teleprompter Word Alignment
        let script = "Welcome everyone to our live product demo. Today we showcase the new teleprompter right under your camera."
        let words = TeleprompterWordAligner.tokenize(script)
        suite.expect(words.count == 17, "teleprompter tokenizer splits words preserving punctuation")
        let idx1 = TeleprompterWordAligner.advanceCursor(currentIndex: 0, spokenText: "Welcome everyone to our live", scriptWords: words)
        suite.expect(idx1 == 4, "exact voice match advances cursor smoothly to last spoken word")
        let idx2 = TeleprompterWordAligner.advanceCursor(currentIndex: idx1, spokenText: "product demo today we showcase the new telaprompter", scriptWords: words)
        suite.expect(idx2 == 12, "fuzzy matching tolerates minor speech recognition typos like telaprompter")
        let idxNoise = TeleprompterWordAligner.advanceCursor(currentIndex: idx2, spokenText: "unrelated background noise zebra giraffe", scriptWords: words)
        suite.expect(idxNoise == idx2, "unrelated background speech does not jump the teleprompter cursor")
        let idxPrefix = TeleprompterWordAligner.advanceCursor(currentIndex: 11, spokenText: "tele", scriptWords: words)
        suite.expect(idxPrefix == 12, "low-latency prefix snap advances immediately on 3+ char prefix of next word")
        let idxNoisyTail = TeleprompterWordAligner.advanceCursor(currentIndex: 1, spokenText: "everyone to um", scriptWords: words)
        suite.expect(idxNoisyTail == 2, "penultimate-token fallback prevents stalling on noisy trailing partial syllable")

        // MARK: 4. AI Agents Multi-Account & Layout Customization
        suite.expect(AgentAccountRegistry.provider(forT3Name: "antigravity_antigravity_2") == .antigravity
                     && AgentAccountRegistry.provider(forT3Name: "codex_work") == .codex
                     && AgentAccountRegistry.provider(forT3Name: "claude-personal") == .claude
                     && AgentAccountRegistry.provider(forT3Name: "opencode") == .opencode,
                     "T3 multi-instance provider names map accurately to their AgentProvider")

        let twoAntigravityAccounts = [
            AgentAccount(id: "ag-1", provider: .antigravity, label: "Work AG", sourcePath: "/tmp/ag1", enabled: true),
            AgentAccount(id: "claude-1", provider: .claude, label: "Claude Pro", sourcePath: "/tmp/claude1", enabled: true),
            AgentAccount(id: "ag-2", provider: .antigravity, label: "Personal AG", sourcePath: "/tmp/ag2", enabled: true),
        ]
        var separateConfig = NotchAgentLayoutConfig.default
        separateConfig.accountCardMode = .separateAccounts
        let separateTiles = NotchAgentSupport.customizedTiles(
            cards: [.limits], providers: [.claude, .antigravity], accounts: twoAntigravityAccounts, config: separateConfig)
        suite.expect(separateTiles.count == 3
                     && separateTiles[0].accountLabel == "Work AG"
                     && separateTiles[1].accountLabel == "Claude Pro"
                     && separateTiles[2].accountLabel == "Personal AG",
                     "separateAccounts mode preserves explicit user account ordering across providers")

        var combinedConfig = NotchAgentLayoutConfig.default
        combinedConfig.accountCardMode = .combinedByProvider
        let combinedTiles = NotchAgentSupport.customizedTiles(
            cards: [.limits], providers: [.antigravity], accounts: twoAntigravityAccounts, config: combinedConfig)
        suite.expect(combinedTiles.count == 1,
                     "combinedByProvider mode consolidates multiple accounts into one card per provider")

        var singleCol = NotchAgentLayoutConfig.default
        singleCol.columnMode = .singleColumn
        let singleColRows = NotchAgentSupport.rows(separateTiles, width: 520, config: singleCol)
        suite.expect(singleColRows.count == 3 && singleColRows.allSatisfy { $0.count == 1 },
                     "single-column layout stacks cards one per row regardless of width")

        // MARK: 5. Focus Mode Parsing & Suppression Guard
        let dndOn = NotchFocusSupport.parseBannerStrings(["Do Not Disturb", "On"])
        suite.expect(dndOn?.isActive == true && dndOn?.name == "Do Not Disturb",
                     "Focus parser recognizes Do Not Disturb On banner")
        let workOff = NotchFocusSupport.parseBannerStrings(["Work", "Off"])
        suite.expect(workOff?.isActive == false && workOff?.name == "Work" && workOff?.tintName == "teal",
                     "Focus parser recognizes Work Off banner with teal tint")
        let normalAppBanner = NotchFocusSupport.parseBannerStrings([
            "Slack", "Alex", "Let's focus on work today and ship the release notes before 5pm so everyone is aligned."
        ])
        suite.expect(normalAppBanner == nil,
                     "ordinary app notifications mentioning focus or work are never misclassified as Focus banners")

        let logLine = Data("{\"eventMessage\":\"DNDStateUpdate active=YES modeIdentifier=com.apple.focus.work\"}".utf8)
        let parsedLog = NotchFocusSupport.parseLogEvent(logLine)
        suite.expect(parsedLog?.isActive == true && parsedLog?.modeIdentifier == "com.apple.focus.work",
                     "Focus unified log parser extracts active flag and modeIdentifier")

        // MARK: 6. Shortcuts Passive Identity
        suite.expect(NotchShortcutIdentityResolver.parseShortcutsCLIArgs(["/usr/bin/shortcuts", "run", "Morning Routine"]) == "Morning Routine",
                     "CLI parser extracts shortcut name from /usr/bin/shortcuts run arguments")
        suite.expect(NotchShortcutIdentityResolver.extractRunningShortcutName(from: "Running “Daily Backup”") == "Daily Backup",
                     "AX title parser extracts quoted running shortcut name")
        suite.expect(NotchShortcutIdentityResolver.inferredSymbol(for: "Play Music Mix") == "music.note",
                     "fallback symbol inference picks contextual SF Symbols")
    }
}
