// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

final class DictationRecorder {
    struct Microphone: Identifiable { let id: String; let name: String; let device: AudioDeviceID }
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private let lock = NSLock()
    private var level = 0.0
    private var writeError: Error?
    private var active = false

    static func microphones() -> [Microphone] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.compactMap { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            func string(_ selector: AudioObjectPropertySelector) -> String? {
                var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var value: Unmanaged<CFString>?
                var length = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                guard AudioObjectGetPropertyData(device, &property, 0, nil, &length, &value) == noErr else { return nil }
                return value?.takeUnretainedValue() as String?
            }
            guard let id = string(kAudioDevicePropertyDeviceUID), let name = string(kAudioObjectPropertyName) else { return nil }
            return Microphone(id: id, name: name, device: device)
        }
    }

    func start(at url: URL, microphoneUID: String) throws {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        if !microphoneUID.isEmpty {
            guard var device = Self.microphones().first(where: { $0.id == microphoneUID })?.device,
                  let unit = node.audioUnit,
                  AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device,
                                       UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
                throw DictationError.message("The selected microphone is unavailable. Choose another input in Dictation settings.")
            }
        }
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationError.message("No microphone input is available.") }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        lock.lock(); self.file = file; active = true; level = 0; writeError = nil; lock.unlock()
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.active else { return }
            do { try self.file?.write(from: buffer) } catch { self.writeError = error; self.active = false }
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            var energy: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) { let sample = channels[channel][frame]; energy += sample * sample }
            }
            let rms = sqrt(energy / Float(buffer.frameLength * buffer.format.channelCount))
            self.level = min(1, max(0, Double(rms) * 6))
        }
        do { try engine.start(); self.engine = engine }
        catch { node.removeTap(onBus: 0); stop(); throw error }
    }

    func reading() -> (level: Double, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        return (level, writeError)
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        lock.lock(); active = false; file = nil; level = 0; lock.unlock()
    }
}
