// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import libzstd

enum AgentCompressedLogTests {
    private static func compressed(_ data: Data) -> Data {
        var result = Data(count: ZSTD_compressBound(data.count))
        let length = result.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in ZSTD_compress(target.baseAddress, target.count, source.baseAddress, source.count, 1) }
        }
        precondition(ZSTD_isError(length) == 0)
        result.count = length
        return result
    }

    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorssaint-compressed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "rollout.jsonl.zst")
            // More than one decoder output buffer; frames concatenate as they
            // do when archived sessions were appended or compressed in chunks.
            let large = Data(repeating: 65, count: 2 << 20)
            try (compressed(large) + compressed(Data("tail".utf8))).write(to: file)
            var output = Data()
            suite.expect(AgentCompressedLogReader.read(file.path, shouldContinue: { true }, chunk: { output.append($0) })
                            && output == large + Data("tail".utf8),
                         "bundled Zstandard decoder streams large concatenated frames without losing buffered output")
            var delivered = false
            suite.expect(!AgentCompressedLogReader.read(file.path, shouldContinue: { false }, chunk: { _ in delivered = true }) && !delivered,
                         "compressed history reading observes cancellation")
            try compressed(large).dropLast(5).write(to: file)
            suite.expect(!AgentCompressedLogReader.read(file.path, shouldContinue: { true }, chunk: { _ in }),
                         "truncated archives never claim a completed read")
            let date = Date().timeIntervalSince1970
            let lines = [
                #"{"type":"session_meta","timestamp":\#(date),"payload":{"id":"archive-test","cwd":"/tmp/example"}}"#,
                #"{"type":"turn_context","timestamp":\#(date),"payload":{"model":"gpt-6.1-sol"}}"#,
                #"{"type":"token_usage_record","timestamp":\#(date),"payload":{"response_id":"r","usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":100}}}"#,
            ]
            let plain = folder.appending(path: "rollout.jsonl")
            let transcript = Data(lines.joined(separator: "\n").utf8)
            try (transcript + Data("\n".utf8)).write(to: plain)
            try compressed(transcript).write(to: file)
            let found = AgentLogReader.discover([AgentLogRoot(provider: .codex, url: folder)], since: .distantPast)
            suite.expect(found.count == 2, "Codex discovers plain and compressed session histories")
            let store = AgentUsageStore()
            for path in [plain.path, file.path] {
                let cursor = AgentLogCursor(path: path, provider: .codex)
                var reads = 0
                func read(_ line: Data) {
                    reads += 1
                    let entries = AgentLogParser.parseCodex(line, state: &cursor.state, now: Date())
                    store.apply(entries, file: path, provider: .codex, tracksTurns: false, modified: Date())
                }
                AgentLogReader.readAppended(cursor, line: read)
                let firstReads = reads
                AgentLogReader.readAppended(cursor, line: read)
                suite.expect(reads == firstReads, "unchanged plain or compressed history is not reparsed")
            }
            suite.expect(store.records.count == 1 && store.records.first?.tokens == AgentTokens(input: 200, cacheRead: 800, output: 100),
                         "plain/compressed copies deduplicate with cached input separated from uncached input")
            suite.expectClose(store.records.first?.cost ?? -1, 0.00148,
                              "compressed Codex history retains the same model cost", tol: 0.0000001)
        } catch { suite.expect(false, "compressed history fixtures: \(error)") }
    }
}
