// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import libzstd

/// Streams Codex's archived .jsonl.zst logs through the same bounded line parser
/// as plain JSONL. No subprocesses, temporary transcripts or machine dependencies.
enum AgentCompressedLogReader {
    static func read(_ path: String, shouldContinue: () -> Bool, chunk: (Data) -> Void) -> Bool {
        guard let file = FileHandle(forReadingAtPath: path), let stream = ZSTD_createDStream() else { return false }
        defer { try? file.close(); ZSTD_freeDStream(stream) }
        // A corrupt archive cannot demand a multi-gigabyte history window.
        guard ZSTD_isError(ZSTD_DCtx_setParameter(stream, ZSTD_d_windowLogMax, 27)) == 0,
              ZSTD_isError(ZSTD_initDStream(stream)) == 0 else { return false }
        var output = [UInt8](repeating: 0, count: 128 << 10)
        var remaining = 1
        var sawData = false
        while shouldContinue() {
            let data: Data
            do { data = try file.read(upToCount: 128 << 10) ?? Data() }
            catch { return false }
            if data.isEmpty { return sawData && remaining == 0 }
            sawData = true
            let success = data.withUnsafeBytes { raw -> Bool in
                var input = ZSTD_inBuffer(src: raw.baseAddress, size: raw.count, pos: 0)
                var drainOutput = false
                while (input.pos < input.size || drainOutput), shouldContinue() {
                    let oldPosition = input.pos
                    let read = output.withUnsafeMutableBytes { dest -> (Int, Int) in
                        var decoded = ZSTD_outBuffer(dst: dest.baseAddress, size: dest.count, pos: 0)
                        let status = ZSTD_decompressStream(stream, &decoded, &input)
                        return (status, decoded.pos)
                    }
                    guard ZSTD_isError(read.0) == 0 else { return false }
                    remaining = read.0
                    drainOutput = read.1 == output.count
                    if read.1 > 0 { chunk(Data(output.prefix(read.1))) }
                    if input.pos == oldPosition && read.1 == 0 { return input.pos == input.size }
                }
                return shouldContinue()
            }
            if !success { return false }
        }
        return false
    }
}
