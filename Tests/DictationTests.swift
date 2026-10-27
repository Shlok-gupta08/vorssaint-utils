// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DictationTests {
    static func run(expect: (Bool, String) -> Void) {
        let original = "  Um, call vorssaint and album art, not callum.  "
        let cleaned = DictationSupport.cleaned(original, replacements: "vorssaint=Vorssaint\nart=Art $1\nbad line", removeFillers: true, language: "en")
        expect(cleaned == "call Vorssaint and album Art $1, not callum.", "corrections honor word boundaries and literal replacement characters")
        expect(DictationSupport.cleaned("Um, test", replacements: "", removeFillers: true, language: "de") == "Um, test",
               "English filler removal never rewrites a different language")
        let root = URL(fileURLWithPath: "/private/dictation")
        let id = UUID()
        expect(DictationSupport.safeAudioURL(filename: id.uuidString + ".caf", directory: root)?.deletingLastPathComponent().path == root.path,
               "valid recording identifiers resolve inside private history")
        for invalid in ["../secret.caf", "/tmp/secret.caf", "anything.caf", "..", id.uuidString + ".wav"] {
            expect(DictationSupport.safeAudioURL(filename: invalid, directory: root) == nil, "history rejects an unsafe recording path")
        }
        let now = Date(timeIntervalSince1970: 2_000_000)
        expect(!DictationSupport.audioExpired(now.addingTimeInterval(-86399), days: 1, now: now)
               && DictationSupport.audioExpired(now.addingTimeInterval(-86400), days: 1, now: now)
               && DictationSupport.audioExpired(now, days: 0, now: now), "audio expiry respects the retention boundary and Never")
        let entries = (0..<5).map { i in DictationEntry(text: "Text \(i)", originalText: "Text \(i)", modelID: "test", language: "en", duration: 1, processingDuration: 0.1, isFavorite: i == 4) }
        expect(DictationSupport.retained(entries, limit: 2).map(\.id) == [entries[0].id, entries[1].id, entries[4].id],
               "history trims old ordinary entries while retaining favorites in order")
        expect(DictationSupport.retained(entries, limit: 0).isEmpty, "turning off history removes favorites too")
        expect((try? JSONDecoder().decode([DictationEntry].self, from: JSONEncoder().encode(entries))) == entries,
               "private history preserves original text, timestamps and favorites across saves")
        expect(AppFeature.dictation.permissions.contains(.microphone) && AppFeature.dictation.permissions.contains(.accessibility)
               && !AppFeature.dictation.installedByDefault, "dictation advertises permissions and remains opt-in")
        for language in AppLanguage.allCases {
            expect(!DictationStrings.localized(language).title.isEmpty && !DictationStrings.localized(language).history.isEmpty,
                   "dictation has core labels in \(language.rawValue)")
        }
    }
}
