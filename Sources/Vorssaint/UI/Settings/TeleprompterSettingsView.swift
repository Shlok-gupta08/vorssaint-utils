// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Speech
import SwiftUI

/// Dedicated Teleprompter settings & script library pane.
struct TeleprompterSettingsView: View {
    @ObservedObject private var prompter = NotchTeleprompterService.shared
    @AppStorage(DefaultsKey.notchTeleprompterEnabled) private var enabled = true
    @State private var editTitle = ""
    @State private var editBody = ""

    private var supportedLocales: [Locale] {
        let list = Array(SFSpeechRecognizer.supportedLocales()).sorted {
            ($0.localizedString(forIdentifier: $0.identifier) ?? $0.identifier)
                < ($1.localizedString(forIdentifier: $1.identifier) ?? $1.identifier)
        }
        return list.isEmpty ? [Locale.current] : list
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Teleprompter in Dynamic Island", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        NotchService.shared.syncWithPreferences()
                    }
                Text("Keep your talking points right under the MacBook camera with automatic voice-tracked scrolling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    NotchService.shared.open(.teleprompter)
                } label: {
                    Label("Open Teleprompter in Dynamic Island", systemImage: "arrow.up.forward.app")
                }
                .disabled(!enabled || !NotchSupport.isEnabled())
            }

            if enabled {
                Section("Voice Tracking & Scrolling") {
                    Picker("Tracking mode", selection: $prompter.settings.trackingMode) {
                        ForEach(TeleprompterTrackingMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    Text(prompter.settings.trackingMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if prompter.settings.trackingMode == .voiceTrack {
                        Picker("Speech language", selection: $prompter.settings.localeIdentifier) {
                            ForEach(supportedLocales, id: \.identifier) { loc in
                                Text(loc.localizedString(forIdentifier: loc.identifier) ?? loc.identifier)
                                    .tag(loc.identifier)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Reading speed")
                            Spacer()
                            Text("\(Int(prompter.settings.wordsPerMinute)) WPM")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $prompter.settings.wordsPerMinute, in: TeleprompterSettings.wpmRange, step: 5)
                    }

                    Picker("Start countdown", selection: $prompter.settings.countdownSeconds) {
                        ForEach(TeleprompterSettings.countdownOptions, id: \.self) { sec in
                            Text(sec == 0 ? "Off" : "\(sec) seconds").tag(sec)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Auto-pin Dynamic Island while prompting", isOn: $prompter.settings.autoPinNotch)
                }

                Section("Appearance") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Font size")
                            Spacer()
                            Text("\(Int(prompter.settings.fontSize)) pt")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $prompter.settings.fontSize, in: TeleprompterSettings.fontSizeRange, step: 1)
                    }
                    Toggle("Show camera-level reading guide", isOn: $prompter.settings.showReadingGuide)
                    Toggle("Mirror text horizontally (for beam-splitter glass)", isOn: $prompter.settings.mirrorHorizontally)
                }

                Section("Script Library") {
                    HStack {
                        Picker("Script", selection: $prompter.selectedScriptID) {
                            ForEach(prompter.scripts) { script in
                                Text("\(script.title) (\(script.wordCount) words)").tag(script.id)
                            }
                        }
                        Button {
                            _ = prompter.createScript(title: "New Script", body: "")
                            syncDraft()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("New script")

                        Button {
                            prompter.importFromClipboard()
                            syncDraft()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .help("New script from clipboard")

                        Button(role: .destructive) {
                            prompter.deleteScript(prompter.selectedScriptID)
                            syncDraft()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(prompter.scripts.count <= 1)
                        .help("Delete selected script")
                    }

                    TextField("Title", text: $editTitle)
                        .onChange(of: editTitle) { _, _ in
                            prompter.updateSelectedScript(title: editTitle, body: editBody)
                        }

                    TextEditor(text: $editBody)
                        .font(.body)
                        .frame(minHeight: 160)
                        .onChange(of: editBody) { _, _ in
                            prompter.updateSelectedScript(title: editTitle, body: editBody)
                        }

                    let est = prompter.selectedScript.estimatedSeconds(wpm: prompter.settings.wordsPerMinute)
                    Text("\(prompter.selectedScript.wordCount) words · ~\(Duration.seconds(est).formatted(.time(pattern: .minuteSecond))) at \(Int(prompter.settings.wordsPerMinute)) WPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { syncDraft() }
        .onChange(of: prompter.selectedScriptID) { _, _ in syncDraft() }
    }

    private func syncDraft() {
        editTitle = prompter.selectedScript.title
        editBody = prompter.selectedScript.body
    }
}
