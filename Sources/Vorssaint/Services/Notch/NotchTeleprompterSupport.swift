// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TeleprompterTrackingMode: String, CaseIterable, Identifiable, Codable {
    case voiceTrack
    case voicePace
    case steadyScroll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voiceTrack: return "Voice Track"
        case .voicePace: return "Voice Pace"
        case .steadyScroll: return "Auto Scroll"
        }
    }

    var symbol: String {
        switch self {
        case .voiceTrack: return "waveform.badge.mic"
        case .voicePace: return "mic.fill"
        case .steadyScroll: return "scroll"
        }
    }

    var description: String {
        switch self {
        case .voiceTrack: return "Follows your spoken words automatically using on-device speech recognition."
        case .voicePace: return "Scrolls smoothly while you speak and pauses automatically during silences."
        case .steadyScroll: return "Scrolls continuously at your chosen reading speed."
        }
    }
}

struct TeleprompterScript: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var body: String
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, body: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
    }

    var words: [TeleprompterWord] {
        TeleprompterWordAligner.tokenize(body)
    }

    var wordCount: Int { words.count }

    func estimatedSeconds(wpm: Double) -> TimeInterval {
        let rate = max(40, wpm)
        return Double(wordCount) / rate * 60.0
    }

    static let sample = TeleprompterScript(
        id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
        title: "Welcome Script",
        body: """
        Welcome to your Dynamic Island Teleprompter. Because this text sits directly underneath your MacBook camera, you can read smoothly while keeping natural eye contact with your audience.

        Turn on Voice Track to let the script follow your voice word by word automatically. Pause anytime to improvise or take a breath, and the prompter waits right where you left off.

        Click any word in the script to jump straight there, or switch to Edit to paste your own talking points.
        """
    )
}

struct TeleprompterSettings: Codable, Equatable {
    var trackingMode: TeleprompterTrackingMode = .voiceTrack
    var wordsPerMinute: Double = 145
    var fontSize: Double = 18
    var lineSpacing: Double = 6
    var mirrorHorizontally: Bool = false
    var showReadingGuide: Bool = true
    var countdownSeconds: Int = 3
    var autoPinNotch: Bool = true
    var localeIdentifier: String = Locale.current.identifier
    var voiceSensitivity: Double = 0.032

    static let `default` = TeleprompterSettings()
    static let wpmRange: ClosedRange<Double> = 60...260
    static let fontSizeRange: ClosedRange<Double> = 13...30
    static let countdownOptions = [0, 3, 5]

    static func current(in defaults: UserDefaults = .standard) -> TeleprompterSettings {
        guard let raw = defaults.string(forKey: DefaultsKey.notchTeleprompterSettings),
              !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TeleprompterSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              let raw = String(data: data, encoding: .utf8) else { return }
        defaults.set(raw, forKey: DefaultsKey.notchTeleprompterSettings)
    }
}

struct TeleprompterWord: Equatable, Identifiable {
    let id: Int
    let text: String
    let normalized: String
    let paragraphIndex: Int
}

struct TeleprompterParagraph: Identifiable, Equatable {
    let id: Int
    let words: [TeleprompterWord]
}

/// Pure, deterministic fuzzy word-alignment engine for real-time voice tracking.
/// Matches incoming spoken words against a bounded lookahead window in the script
/// using phrase (2-gram/3-gram) scoring and bounded Levenshtein tolerance.
enum TeleprompterWordAligner {
    static func normalize(_ token: String) -> String {
        let lowered = token.lowercased()
        let scalars = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    static func tokenize(_ text: String) -> [TeleprompterWord] {
        let paragraphs = text.components(separatedBy: .newlines)
        var words: [TeleprompterWord] = []
        var paragraphIndex = 0
        for rawParagraph in paragraphs {
            let trimmed = rawParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let rawTokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            for token in rawTokens {
                let norm = normalize(token)
                words.append(TeleprompterWord(
                    id: words.count,
                    text: token,
                    normalized: norm,
                    paragraphIndex: paragraphIndex
                ))
            }
            paragraphIndex += 1
        }
        return words
    }

    static func paragraphs(from words: [TeleprompterWord]) -> [TeleprompterParagraph] {
        var grouped: [Int: [TeleprompterWord]] = [:]
        for w in words { grouped[w.paragraphIndex, default: []].append(w) }
        return grouped.keys.sorted().map { TeleprompterParagraph(id: $0, words: grouped[$0] ?? []) }
    }

    /// Advances the script cursor based on the latest spoken transcript.
    /// Never jumps wildly past a bounded lookahead window so repeated filler words
    /// or misrecognitions cannot derail the teleprompter.
    static func advanceCursor(currentIndex: Int,
                              spokenText: String,
                              scriptWords: [TeleprompterWord],
                              lookahead: Int = 20) -> Int {
        guard !scriptWords.isEmpty else { return 0 }
        let safeCurrent = min(max(0, currentIndex), scriptWords.count - 1)
        // Only inspect the tail of the running transcript so long talks stay O(1).
        let tailSlice = spokenText.count > 160 ? String(spokenText.suffix(160)) : spokenText
        let spokenTokens = tailSlice
            .split(whereSeparator: \.isWhitespace)
            .suffix(8)
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
        guard !spokenTokens.isEmpty else { return safeCurrent }

        // Focus on the tail of what was most recently spoken.
        let recent = Array(spokenTokens.suffix(6))
        let windowEnd = min(scriptWords.count - 1, safeCurrent + lookahead)

        // 1. Prefer 2-word and 3-word consecutive phrase matches in the lookahead window.
        if recent.count >= 2 {
            let pair = Array(recent.suffix(2))
            var bestPairIndex: Int?
            var bestScore = 0
            for idx in safeCurrent...windowEnd {
                guard idx + 1 < scriptWords.count else { continue }
                let m0 = tokensMatch(pair[0], scriptWords[idx].normalized)
                let m1 = tokensMatch(pair[1], scriptWords[idx + 1].normalized)
                if m0 && m1 {
                    var score = 100 - (idx - safeCurrent) * 2
                    if recent.count >= 3, idx > 0,
                       tokensMatch(recent[recent.count - 3], scriptWords[idx - 1].normalized) {
                        score += 40
                    }
                    if score > bestScore {
                        bestScore = score
                        bestPairIndex = idx + 1
                    }
                }
            }
            if let bestPairIndex {
                return min(scriptWords.count - 1, bestPairIndex)
            }
        }

        // 2. Single-word match in a tighter immediate window (closest first).
        let lastSpoken = recent.last!
        let singleEnd = min(scriptWords.count - 1, safeCurrent + 8)
        for idx in safeCurrent...singleEnd {
            if tokensMatch(lastSpoken, scriptWords[idx].normalized) {
                // Require non-trivial length (>2 chars) if skipping ahead more than 2 words.
                if idx > safeCurrent + 2 && lastSpoken.count <= 2 { continue }
                return idx
            }
        }

        // 3. Low-latency partial-word snap: if the user is mid-word on the immediately
        // next 1–2 words, advance as soon as a 3+ character prefix matches.
        if lastSpoken.count >= 3 {
            let nextStart = min(scriptWords.count - 1, safeCurrent + 1)
            let nextEnd = min(scriptWords.count - 1, safeCurrent + 2)
            if nextStart <= nextEnd {
                for idx in nextStart...nextEnd {
                    let target = scriptWords[idx].normalized
                    if target.count >= lastSpoken.count && target.hasPrefix(lastSpoken) {
                        return idx
                    }
                }
            }
        }

        // 4. Penultimate-token fallback: if ASR emitted a noisy trailing syllable,
        // don't stall if the previous token already matched an immediately upcoming word.
        if recent.count >= 2 {
            let prevSpoken = recent[recent.count - 2]
            let immediateEnd = min(scriptWords.count - 1, safeCurrent + 4)
            let nextStart = min(scriptWords.count - 1, safeCurrent + 1)
            if nextStart <= immediateEnd {
                for idx in nextStart...immediateEnd {
                    if tokensMatch(prevSpoken, scriptWords[idx].normalized) {
                        if idx > safeCurrent + 2 && prevSpoken.count <= 2 { continue }
                        return idx
                    }
                }
            }
        }

        return safeCurrent
    }

    static func tokensMatch(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        if a.count >= 4, b.count >= 4 {
            if a.hasPrefix(b) || b.hasPrefix(a) {
                return abs(a.count - b.count) <= 2
            }
            return editDistanceAtMostOne(a, b)
        }
        return false
    }

    private static func editDistanceAtMostOne(_ a: String, _ b: String) -> Bool {
        let ca = Array(a), cb = Array(b)
        if abs(ca.count - cb.count) > 1 { return false }
        var i = 0, j = 0, edits = 0
        while i < ca.count && j < cb.count {
            if ca[i] == cb[j] {
                i += 1; j += 1
            } else {
                edits += 1
                if edits > 1 { return false }
                if ca.count > cb.count { i += 1 }
                else if cb.count > ca.count { j += 1 }
                else { i += 1; j += 1 }
            }
        }
        if i < ca.count || j < cb.count { edits += 1 }
        return edits <= 1
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && AppFeature.teleprompter.isAvailable(in: defaults)
            && (defaults.object(forKey: DefaultsKey.notchTeleprompterEnabled) as? Bool ?? true)
            && NotchSupport.modules(in: defaults).contains(.teleprompter)
    }
}
