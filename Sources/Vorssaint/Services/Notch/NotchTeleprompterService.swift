// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit
import Combine
import Foundation
import Speech

/// Isolated high-frequency audio meter state so mic level updates never trigger
/// full SwiftUI layout passes of the teleprompter word flow.
final class TeleprompterAudioMeter: ObservableObject {
    @Published var micLevel: Double = 0
    @Published var isVoiceActive = false

    func reset() {
        if micLevel != 0 { micLevel = 0 }
        if isVoiceActive { isVoiceActive = false }
    }
}

/// Manages Teleprompter scripts, playback, steady/voice-pace scrolling, and
/// real-time on-device speech-synced word tracking.
final class NotchTeleprompterService: ObservableObject {
    static let shared = NotchTeleprompterService()

    let audioMeter = TeleprompterAudioMeter()

    @Published var scripts: [TeleprompterScript] = []
    @Published var selectedScriptID: UUID = TeleprompterScript.sample.id {
        didSet {
            UserDefaults.standard.set(selectedScriptID.uuidString, forKey: DefaultsKey.notchTeleprompterSelectedID)
            rebuildTokens()
            if isPlaying { stop() }
        }
    }
    @Published var settings: TeleprompterSettings = .default {
        didSet {
            settings.save()
            if isPlaying && !isPaused {
                reconfigureActiveTracking()
            }
        }
    }

    @Published private(set) var words: [TeleprompterWord] = []
    @Published private(set) var paragraphs: [TeleprompterParagraph] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var countdownRemaining = 0
    @Published private(set) var currentWordIndex = 0
    @Published private(set) var voiceStatusMessage: String?
    private(set) var lastHeardPhrase: String = ""

    var micLevel: Double { audioMeter.micLevel }
    var isVoiceActive: Bool { audioMeter.isVoiceActive }

    var selectedScript: TeleprompterScript {
        scripts.first(where: { $0.id == selectedScriptID }) ?? scripts.first ?? .sample
    }

    var progress: Double {
        guard words.count > 1 else { return words.isEmpty ? 0 : 1 }
        return min(1, max(0, Double(currentWordIndex) / Double(words.count - 1)))
    }

    var hasLiveActivity: Bool {
        isPlaying && TeleprompterWordAligner.isEnabled()
    }

    private var scrollTimer: Timer?
    private var countdownWork: DispatchWorkItem?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRestartWork: DispatchWorkItem?
    private var lastVoiceDetectedAt = Date.distantPast
    private var wordAccumulator: Double = 0
    private var lastTickAt = Date()
    private var pinnedByTeleprompter = false
    private var trackingGeneration = UUID()

    private init() {
        loadPersistedState()
    }

    // MARK: - Persistence & Script CRUD

    private func loadPersistedState() {
        settings = TeleprompterSettings.current()
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.notchTeleprompterScripts),
           !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TeleprompterScript].self, from: data),
           !decoded.isEmpty {
            scripts = decoded
        } else {
            scripts = [.sample]
        }

        if let savedID = UserDefaults.standard.string(forKey: DefaultsKey.notchTeleprompterSelectedID),
           let uuid = UUID(uuidString: savedID),
           scripts.contains(where: { $0.id == uuid }) {
            selectedScriptID = uuid
        } else {
            selectedScriptID = scripts[0].id
        }
        rebuildTokens()
    }

    private func persistScripts() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(scripts),
              let raw = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(raw, forKey: DefaultsKey.notchTeleprompterScripts)
    }

    private func rebuildTokens() {
        let tokenized = selectedScript.words
        words = tokenized
        paragraphs = TeleprompterWordAligner.paragraphs(from: tokenized)
        if currentWordIndex >= words.count {
            currentWordIndex = 0
        }
    }

    @discardableResult
    func createScript(title: String = "Untitled Script", body: String = "") -> TeleprompterScript {
        let created = TeleprompterScript(title: title, body: body)
        scripts.insert(created, at: 0)
        persistScripts()
        selectedScriptID = created.id
        currentWordIndex = 0
        return created
    }

    func updateSelectedScript(title: String, body: String) {
        guard let idx = scripts.firstIndex(where: { $0.id == selectedScriptID }) else { return }
        scripts[idx].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Script" : title
        scripts[idx].body = body
        scripts[idx].updatedAt = Date()
        persistScripts()
        rebuildTokens()
    }

    func deleteScript(_ id: UUID) {
        scripts.removeAll { $0.id == id }
        if scripts.isEmpty {
            scripts = [.sample]
        }
        if !scripts.contains(where: { $0.id == selectedScriptID }) {
            selectedScriptID = scripts[0].id
        }
        persistScripts()
        rebuildTokens()
    }

    func importFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        let firstLine = text.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Clipboard Script"
        let title = String(firstLine.prefix(32))
        _ = createScript(title: title.isEmpty ? "Clipboard Script" : title, body: text)
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        if !isPlaying {
            play()
        } else if isPaused {
            resume()
        } else {
            pause()
        }
    }

    func play() {
        guard !words.isEmpty else { return }
        if currentWordIndex >= words.count - 1 {
            currentWordIndex = 0
        }
        if settings.autoPinNotch && !NotchService.shared.pinned {
            NotchService.shared.pinned = true
            pinnedByTeleprompter = true
        }
        isPlaying = true
        isPaused = false
        voiceStatusMessage = nil

        if settings.countdownSeconds > 0 {
            startCountdown(settings.countdownSeconds)
        } else {
            beginActivePrompting()
        }
    }

    func pause() {
        guard isPlaying, !isPaused else { return }
        countdownWork?.cancel(); countdownWork = nil
        countdownRemaining = 0
        isPaused = true
        stopTrackingEngines()
    }

    func resume() {
        guard isPlaying, isPaused else { return }
        isPaused = false
        beginActivePrompting()
    }

    func stop() {
        countdownWork?.cancel(); countdownWork = nil
        countdownRemaining = 0
        stopTrackingEngines()
        isPlaying = false
        isPaused = false
        audioMeter.reset()
        voiceStatusMessage = nil
        lastHeardPhrase = ""
        if pinnedByTeleprompter {
            pinnedByTeleprompter = false
            NotchService.shared.pinned = false
        }
    }

    func restart() {
        currentWordIndex = 0
        wordAccumulator = 0
        lastHeardPhrase = ""
        if isPlaying && !isPaused {
            reconfigureActiveTracking()
        }
    }

    func jumpTo(wordIndex: Int) {
        guard !words.isEmpty else { return }
        currentWordIndex = min(max(0, wordIndex), words.count - 1)
        wordAccumulator = 0
    }

    func stepWords(_ delta: Int) {
        jumpTo(wordIndex: currentWordIndex + delta)
    }

    // MARK: - Countdown

    private func startCountdown(_ seconds: Int) {
        countdownWork?.cancel()
        countdownRemaining = seconds
        tickCountdown()
    }

    private func tickCountdown() {
        guard isPlaying, !isPaused else { countdownRemaining = 0; return }
        if countdownRemaining <= 0 {
            countdownWork = nil
            beginActivePrompting()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPlaying, !self.isPaused else { return }
            self.countdownRemaining -= 1
            self.tickCountdown()
        }
        countdownWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: - Active Tracking Engines

    private func reconfigureActiveTracking() {
        stopTrackingEngines()
        beginActivePrompting()
    }

    private func beginActivePrompting() {
        stopTrackingEngines()
        let gen = UUID()
        trackingGeneration = gen
        lastTickAt = Date()
        wordAccumulator = 0

        switch settings.trackingMode {
        case .steadyScroll:
            voiceStatusMessage = "Auto-scrolling at \(Int(settings.wordsPerMinute)) WPM"
            startScrollTimer(requireVoice: false)
        case .voicePace:
            requestMicAndStart(speechRecognition: false, generation: gen)
        case .voiceTrack:
            requestMicAndStart(speechRecognition: true, generation: gen)
        }
    }

    private func stopTrackingEngines() {
        trackingGeneration = UUID()
        scrollTimer?.invalidate(); scrollTimer = nil
        recognitionRestartWork?.cancel(); recognitionRestartWork = nil
        recognitionTask?.cancel(); recognitionTask = nil
        recognitionRequest?.endAudio(); recognitionRequest = nil
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
            audioEngine = nil
        }
        audioMeter.reset()
    }

    private func startScrollTimer(requireVoice: Bool) {
        scrollTimer?.invalidate()
        lastTickAt = Date()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying, !self.isPaused else { return }
            let now = Date()
            let dt = min(0.25, max(0, now.timeIntervalSince(self.lastTickAt)))
            self.lastTickAt = now
            if requireVoice {
                let speaking = now.timeIntervalSince(self.lastVoiceDetectedAt) < 0.65
                if self.audioMeter.isVoiceActive != speaking { self.audioMeter.isVoiceActive = speaking }
                guard speaking else { return }
            }
            let wordsPerSecond = max(40, self.settings.wordsPerMinute) / 60.0
            self.wordAccumulator += wordsPerSecond * dt
            let steps = Int(self.wordAccumulator)
            if steps > 0 {
                self.wordAccumulator -= Double(steps)
                let next = min(self.words.count - 1, self.currentWordIndex + steps)
                if next != self.currentWordIndex {
                    self.currentWordIndex = next
                }
                if self.currentWordIndex >= self.words.count - 1 {
                    self.pause()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    private func requestMicAndStart(speechRecognition: Bool, generation: UUID) {
        let startAudio: () -> Void = { [weak self] in
            guard let self, self.trackingGeneration == generation, self.isPlaying, !self.isPaused else { return }
            if speechRecognition {
                SFSpeechRecognizer.requestAuthorization { [weak self] status in
                    DispatchQueue.main.async {
                        guard let self, self.trackingGeneration == generation, self.isPlaying, !self.isPaused else { return }
                        if status == .authorized {
                            self.startAudioAndSpeechEngine(withRecognition: true, generation: generation)
                        } else {
                            self.voiceStatusMessage = "Speech permission needed — using Voice Pace"
                            self.startAudioAndSpeechEngine(withRecognition: false, generation: generation)
                            self.startScrollTimer(requireVoice: true)
                        }
                    }
                }
            } else {
                self.voiceStatusMessage = "Speak to scroll · pauses on silence"
                self.startAudioAndSpeechEngine(withRecognition: false, generation: generation)
                self.startScrollTimer(requireVoice: true)
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startAudio()
        case .notDetermined:
            voiceStatusMessage = "Requesting microphone access…"
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.trackingGeneration == generation, self.isPlaying, !self.isPaused else { return }
                    if granted {
                        startAudio()
                    } else {
                        self.voiceStatusMessage = "Mic access denied — using Auto Scroll"
                        self.startScrollTimer(requireVoice: false)
                    }
                }
            }
        default:
            voiceStatusMessage = "Mic access denied — using Auto Scroll"
            startScrollTimer(requireVoice: false)
        }
    }

    private func startAudioAndSpeechEngine(withRecognition: Bool, generation: UUID) {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            voiceStatusMessage = "No microphone input — using Auto Scroll"
            startScrollTimer(requireVoice: false)
            return
        }

        if withRecognition {
            let locale = Locale(identifier: settings.localeIdentifier)
            let speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            guard let speechRecognizer, speechRecognizer.isAvailable else {
                voiceStatusMessage = "Speech unavailable — using Voice Pace"
                startAudioAndSpeechEngine(withRecognition: false, generation: generation)
                startScrollTimer(requireVoice: true)
                return
            }
            recognizer = speechRecognizer
            startRecognitionTask(recognizer: speechRecognizer, generation: generation)
        }

        let sensitivity = settings.voiceSensitivity
        // Use a small 512-frame tap (~10ms at 48kHz) so audio reaches the on-device
        // speech recognizer with minimal buffering latency, and throttle meter UI
        // updates to ~15 Hz on an isolated ObservableObject so word flow never reflows.
        var lastMeterPush = CFAbsoluteTimeGetCurrent()
        var smoothedLevel: Double = 0
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)

            // Compute RMS level for visual meter & Voice Pace VAD.
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            var sumSquares: Float = 0
            // Stride by 2 to halve CPU work on the realtime audio thread.
            var i = 0
            while i < frameLength {
                let s = channelData[i]
                sumSquares += s * s
                i += 2
            }
            let samples = max(1, (frameLength + 1) / 2)
            let rms = sqrt(sumSquares / Float(samples))
            let normalized = min(1.0, max(0.0, Double(rms) * 8.5))
            smoothedLevel = smoothedLevel * 0.55 + normalized * 0.45

            let nowTime = CFAbsoluteTimeGetCurrent()
            let voiceHit = Double(rms) >= sensitivity
            guard voiceHit || (nowTime - lastMeterPush) >= 0.065 else { return }
            lastMeterPush = nowTime
            let levelToPublish = smoothedLevel
            DispatchQueue.main.async { [weak self] in
                guard let self, self.trackingGeneration == generation else { return }
                if abs(self.audioMeter.micLevel - levelToPublish) > 0.025 {
                    self.audioMeter.micLevel = levelToPublish
                }
                if voiceHit {
                    self.lastVoiceDetectedAt = Date()
                    if !self.audioMeter.isVoiceActive { self.audioMeter.isVoiceActive = true }
                } else if Date().timeIntervalSince(self.lastVoiceDetectedAt) > 0.65 {
                    if self.audioMeter.isVoiceActive { self.audioMeter.isVoiceActive = false }
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            audioEngine = engine
        } catch {
            inputNode.removeTap(onBus: 0)
            voiceStatusMessage = "Audio error — using Auto Scroll"
            startScrollTimer(requireVoice: false)
        }
    }

    private func contextualStringsForScript() -> [String] {
        guard !words.isEmpty else { return [] }
        let start = max(0, currentWordIndex)
        let end = min(words.count, start + 120)
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(100)
        for word in words[start..<end] {
            let clean = word.text.trimmingCharacters(in: .punctuationCharacters)
            guard clean.count >= 3 else { continue }
            let key = word.normalized
            if seen.insert(key).inserted {
                result.append(clean)
                if result.count >= 100 { break }
            }
        }
        return result
    }

    private func startRecognitionTask(recognizer: SFSpeechRecognizer, generation: UUID) {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStringsForScript()
        if #available(macOS 13.0, *) {
            request.addsPunctuation = false
        }
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            voiceStatusMessage = "Voice Track · On-Device"
        } else {
            voiceStatusMessage = "Voice Track · Listening"
        }
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.trackingGeneration == generation, self.isPlaying, !self.isPaused else { return }
                if let result {
                    let spoken = result.bestTranscription.formattedString
                    self.lastHeardPhrase = String(spoken.suffix(48))
                    let next = TeleprompterWordAligner.advanceCursor(
                        currentIndex: self.currentWordIndex,
                        spokenText: spoken,
                        scriptWords: self.words
                    )
                    if next != self.currentWordIndex {
                        self.currentWordIndex = next
                    }
                    if self.currentWordIndex >= self.words.count - 1 {
                        self.pause()
                        return
                    }
                }
                if error != nil || result?.isFinal == true {
                    // Seamlessly rotate recognition session before/at Apple's session limit.
                    self.scheduleRecognitionRotation(recognizer: recognizer, generation: generation, delay: 0.1)
                }
            }
        }

        // Proactively rotate at 50s so long talks never hit Apple's ~60s task timeout.
        scheduleRecognitionRotation(recognizer: recognizer, generation: generation, delay: 50)
    }

    private func scheduleRecognitionRotation(recognizer: SFSpeechRecognizer, generation: UUID, delay: TimeInterval) {
        recognitionRestartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.trackingGeneration == generation, self.isPlaying, !self.isPaused,
                  self.settings.trackingMode == .voiceTrack else { return }
            self.startRecognitionTask(recognizer: recognizer, generation: generation)
        }
        recognitionRestartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
