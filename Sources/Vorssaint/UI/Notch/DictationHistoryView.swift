// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DictationHistoryView: View {
    var compact = false
    @ObservedObject private var history = DictationHistoryStore.shared
    @ObservedObject private var speech = DictationService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var editing: DictationEntry?
    @State private var editedText = ""
    @State private var confirmsClear = false
    private var text: DictationStrings { .localized(l10n.language) }
    private var matches: [DictationEntry] {
        history.entries.filter { (!favoritesOnly || $0.isFavorite) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.originalText.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(text.history, text: $query).textFieldStyle(.plain)
                        .accessibilityLabel(text.history)
                }.padding(9).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                Button { favoritesOnly.toggle() } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }.help("Favorites").accessibilityLabel("Favorites").buttonStyle(.plain)
                Menu {
                    Button(text.start, action: speech.toggle).disabled(!speech.isEnabled || speech.phase.isBusy)
                    Button("Transcribe audio file…", action: speech.importAudio).disabled(!speech.isEnabled || speech.phase.isBusy)
                    Button("Export history…", action: exportHistory).disabled(matches.isEmpty)
                    Button("Clear history…", role: .destructive) { confirmsClear = true }.disabled(history.entries.isEmpty)
                    Button(text.title + " settings") {
                        SettingsRouter.shared.request(FeatureSettingsDestination(.dictation))
                        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
            if let error = history.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if matches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 28, weight: .light)).foregroundStyle(.mint)
                    Text(query.isEmpty ? text.empty : "No matching transcripts").font(.system(size: 12, weight: .medium))
                    if query.isEmpty {
                        Button(text.start, action: speech.toggle).disabled(!speech.isEnabled || speech.phase.isBusy)
                            .buttonStyle(.bordered)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(matches) { entry in card(entry) }
                    }
                }.scrollIndicators(.automatic)
            }
            HStack {
                Text("\(matches.count) · " + text.history).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("On this Mac").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .onAppear { history.syncWithPreferences() }
        .confirmationDialog("Clear speech history and its recordings?", isPresented: $confirmsClear) {
            Button("Clear history", role: .destructive, action: history.clear)
        }
        .sheet(item: $editing) { entry in
            VStack(alignment: .leading, spacing: 14) {
                Text(text.history).font(.headline)
                TextEditor(text: $editedText).font(.body).frame(minWidth: 380, minHeight: 200)
                if entry.originalText != entry.text {
                    DisclosureGroup("Original transcription") { Text(entry.originalText).textSelection(.enabled).font(.caption) }
                }
                HStack {
                    Button(text.cancel) { editing = nil }
                    Spacer()
                    Button("Save") { history.update(entry.id, text: editedText); editing = nil }.keyboardShortcut(.defaultAction)
                }
            }.padding(20)
        }
        .accessibilityIdentifier("dictation.history")
    }

    private func card(_ entry: DictationEntry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(entry.text).font(.system(size: compact ? 12 : 13)).lineLimit(compact ? 3 : 6)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            HStack(spacing: 10) {
                Text(entry.createdAt, style: .relative).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(Duration.seconds(entry.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                action("doc.on.doc", title: FeatureStrings.clipboard(l10n.language).copy) { speech.copyEntry(entry) }
                action(entry.isFavorite ? "star.fill" : "star", title: "Favorite") { history.favorite(entry.id) }
                Menu {
                    Button("Edit transcript…") { editedText = entry.text; editing = entry }
                    if history.audioURL(entry) != nil {
                        Button("Play recording") { history.play(entry) }
                        Button("Transcribe again") { speech.retry(entry) }.disabled(speech.phase.isBusy || !speech.isEnabled)
                    }
                    Button("Delete", role: .destructive) { history.remove(entry.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
        }
        .padding(compact ? 11 : 14)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func action(_ symbol: String, title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: symbol).font(.system(size: 11)) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Speech history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(matches).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { NSSound.beep() }
    }
}
