// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation

enum DictationError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Serial, crash-isolated native inference. A warm worker keeps its model in
/// memory between utterances. Cancellation kills it without blocking the UI.
final class DictationEngine {
    struct Request {
        let audio: URL
        let model: URL
        let language: String
        let translate: Bool
        let vocabulary: [String]
        let cpu: Bool
    }
    struct Result: Decodable { let text: String?; let language: String?; let error: String? }
    private let queue = DispatchQueue(label: "com.vorssaint.dictation.engine", qos: .userInitiated)
    private let lock = NSLock()
    private var process: Process?
    private var lifetime = UUID()
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()

    func cancel() {
        lock.lock()
        lifetime = UUID()
        let active = process
        process = nil
        lock.unlock()
        if let active, active.isRunning {
            // SIGKILL also stops unresponsive native/GPU code. All state is private
            // to the worker; no in-process model is left in a half-cancelled state.
            kill(active.processIdentifier, SIGKILL)
        }
    }

    func transcribe(_ request: Request, completion: @escaping (Swift.Result<Result, Error>) -> Void) {
        lock.lock(); let token = lifetime; lock.unlock()
        queue.async {
            var pcm: URL?
            do {
                self.lock.lock(); let valid = self.lifetime == token; self.lock.unlock()
                guard valid else { throw CancellationError() }
                pcm = try Self.convertAudio(request.audio)
                defer { if let pcm { try? FileManager.default.removeItem(at: pcm) } }
                try self.startWorker(token: token)
                let payload: [String: Any] = ["audio": pcm!.path, "model": request.model.path,
                    "language": request.language, "translate": request.translate,
                    "vocabulary": request.vocabulary, "cpu": request.cpu]
                var bytes = try JSONSerialization.data(withJSONObject: payload)
                bytes.append(10)
                try self.input?.write(contentsOf: bytes)
                let reply = try self.readReply()
                if let error = reply.error { throw DictationError.message("Transcription failed: \(error)") }
                guard reply.text != nil else { throw DictationError.message("The dictation engine returned an invalid result.") }
                DispatchQueue.main.async { completion(.success(reply)) }
            } catch {
                if let pcm { try? FileManager.default.removeItem(at: pcm) }
                self.lock.lock(); let current = self.lifetime == token; self.lock.unlock()
                if current { self.cancel() }
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func startWorker(token: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard lifetime == token else { throw CancellationError() }
        if process?.isRunning == true { return }
        try? input?.close(); try? output?.close(); pending.removeAll()
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/VorssaintDictationWorker")
        let development = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("VorssaintDictationWorker")
        let executable = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : development
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DictationError.message("The local speech engine is missing. Rebuild Vorssaint with Tools/build-dictation-engine.sh.")
        }
        let worker = Process()
        let toWorker = Pipe(), fromWorker = Pipe()
        worker.executableURL = executable
        worker.standardInput = toWorker
        worker.standardOutput = fromWorker
        worker.standardError = FileHandle.nullDevice
        try worker.run()
        input = toWorker.fileHandleForWriting
        output = fromWorker.fileHandleForReading
        process = worker
    }

    private func readReply() throws -> Result {
        while true {
            if let newline = pending.firstIndex(of: 10) {
                let line = pending[..<newline]
                pending.removeSubrange(...newline)
                return try JSONDecoder().decode(Result.self, from: line)
            }
            guard pending.count < 16 * 1024 * 1024, let output else { throw DictationError.message("Invalid speech-engine response.") }
            let data = output.availableData
            guard !data.isEmpty else { throw DictationError.message("The speech engine stopped unexpectedly. Try CPU mode in Dictation settings.") }
            pending.append(data)
        }
    }

    /// AVFoundation decodes/resamples all supported imports into the engine's
    /// 16 kHz mono float32 format, with a bounded buffer and no shell commands.
    static func convertAudio(_ source: URL) throws -> URL {
        let file = try AVAudioFile(forReading: source)
        guard file.length > 0, Double(file.length) / file.processingFormat.sampleRate <= 3600,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 32768),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768),
              let directory = PrivateFileStore.containerURL?.appendingPathComponent("Dictation/Temporary", isDirectory: true),
              PrivateFileStore.createDirectory(at: directory) else {
            throw DictationError.message("Choose a nonempty audio file shorter than one hour.")
        }
        let target = directory.appendingPathComponent(UUID().uuidString + ".f32")
        guard FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw DictationError.message("Could not create temporary audio.")
        }
        do {
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            var readError: Error?
            while true {
                var conversionError: NSError?
                let status = converter.convert(to: output, error: &conversionError) { requested, state in
                    do {
                        try file.read(into: input, frameCount: min(requested, input.frameCapacity))
                        state.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                        return input.frameLength == 0 ? nil : input
                    } catch { readError = error; state.pointee = .endOfStream; return nil }
                }
                if let readError { throw readError }
                if let conversionError { throw conversionError }
                if output.frameLength > 0, let samples = output.floatChannelData?[0] {
                    try handle.write(contentsOf: Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Float>.size))
                }
                if status == .endOfStream { break }
                if status == .error { throw DictationError.message("Audio conversion failed.") }
            }
            return target
        } catch { try? FileManager.default.removeItem(at: target); throw error }
    }
}
