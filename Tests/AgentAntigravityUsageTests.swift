// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

enum AgentAntigravityUsageTests {
    private static func varint(_ number: Int) -> Data {
        var n = UInt64(number), result = Data()
        while n >= 128 { result.append(UInt8(n & 127) | 128); n >>= 7 }
        result.append(UInt8(n)); return result
    }
    private static func number(_ field: Int, _ value: Int) -> Data { varint(field << 3) + varint(value) }
    private static func bytes(_ field: Int, _ value: Data) -> Data { varint(field << 3 | 2) + varint(value.count) + value }
    private static func text(_ field: Int, _ value: String) -> Data { bytes(field, Data(value.utf8)) }
    private static func hex(_ data: Data) -> String { "X'" + data.map { String(format: "%02x", $0) }.joined() + "'" }

    static func run(_ suite: TestSuite) {
        do { try database(suite) } catch { suite.expect(false, "Antigravity database fixtures: \(error)") }
    }

    private static func database(_ suite: TestSuite) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorssaint-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "conversation.db")
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        suite.expect(sqlite3_open(file.path, &db) == SQLITE_OK, "Antigravity fixture opens")
        func execute(_ sql: String) { suite.expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "Antigravity metadata fixture SQL succeeds") }
        execute("PRAGMA journal_mode=WAL; CREATE TABLE gen_metadata(idx INTEGER PRIMARY KEY, data BLOB); CREATE TABLE steps(idx INTEGER PRIMARY KEY, metadata BLOB); CREATE TABLE trajectory_metadata_blob(data BLOB);")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stamp = number(1, Int(now.timeIntervalSince1970) - 10)
        execute("INSERT INTO trajectory_metadata_blob VALUES (\(hex(bytes(2, stamp))))")
        func usage(_ input: Int, request: String = "request", extra: Data = Data(), model: Int = 1318) -> Data {
            number(1, model) + number(2, input) + number(3, 15) + number(4, 20) + number(5, 1000)
                + number(9, 10) + number(10, 10) + text(11, request) + extra
        }
        func generation(_ input: Int) -> Data {
            bytes(1, number(3, 1318) + text(19, "gemini-3.8-flash-n")
                + bytes(4, usage(input, extra: text(12, "bridge")))
                + bytes(17, bytes(2, usage(5, request: "retry"))) + bytes(9, bytes(4, stamp)))
        }
        execute("INSERT INTO gen_metadata VALUES (0, \(hex(generation(100))))")
        // A step bridges a different request alias to the same generation.
        let step = bytes(9, usage(120, request: "step-request", extra: text(12, "bridge"))) + bytes(8, stamp)
        execute("INSERT INTO steps VALUES (0, \(hex(step)))")
        execute("INSERT INTO gen_metadata VALUES (1, X'0AFF')")
        let reader = AgentAntigravityUsageReader()
        let horizon = now.addingTimeInterval(-3600)
        let first = reader.read(roots: [folder, folder], since: horizon, now: now, force: true) ?? []
        suite.expect(first.count == 2, "step/generation aliases deduplicate, retries count separately, malformed metadata is skipped")
        suite.expect(first.reduce(0) { $0 + $1.record.tokens.input } == 125,
                     "duplicate counters use maxima without adding the same request twice")
        suite.expect(first.allSatisfy { $0.record.tokens.output == 20 && $0.record.tokens.reasoning == 10 },
                     "thinking and visible output are included once, even when provider output lags")
        suite.expect(first.allSatisfy { $0.record.model == "gemini-3.8-flash-n" && $0.record.cost != nil },
                     "concrete model metadata teaches unnamed steps and preserves the Flash n identity")
        suite.expect(AgentPricing.price(for: "gemini-3.8-flash-n") == AgentPricing.price(for: "gemini-3.8-flash-high")
                     && AgentPricing.price(for: "gemini-3.8-flash-n")?.input == 0.75,
                     "Flash n uses the requested Flash high estimate")
        suite.expect(AgentPricing.price(for: "gemini-3-flash-agent-a") == AgentPricing.price(for: "gemini-3.5-flash")
                        && AgentPricing.price(for: "gemini-3-flash-thinking") == AgentPricing.price(for: "gemini-3-flash-preview")
                        && AgentPricing.price(for: "gemini-3.9-flash-n") == nil
                        && AgentPricing.price(for: "gemini-3.8-flash-cyber") == nil,
                     "known runtime aliases resolve while new versions and specialized siblings stay unpriced")
        let inputCost: Double = 125 * 0.75
        let cacheWriteCost: Double = 40 * 0.75
        let cacheReadCost: Double = 2000 * 0.075
        let outputCost: Double = 40 * 3.75
        let expected = (inputCost + cacheWriteCost + cacheReadCost + outputCost) / 1_000_000
        suite.expectClose(first.reduce(0) { $0 + ($1.record.cost ?? 0) }, expected,
                          "input, cache writes, cache reads and output are priced independently", tol: 0.0000001)
        suite.expect(reader.read(roots: [folder], since: horizon, now: now.addingTimeInterval(11)) == nil,
                     "unchanged databases reuse their decoded metadata")
        execute("UPDATE gen_metadata SET data=\(hex(generation(200))) WHERE idx=0")
        let updated = reader.read(roots: [folder], since: horizon, now: now.addingTimeInterval(22)) ?? []
        suite.expect(updated.count == 2 && updated.reduce(0) { $0 + $1.record.tokens.input } == 205,
                     "WAL-only updates refresh existing usage without counting another response")
        suite.expect(reader.read(roots: [folder], since: horizon, now: now, force: true, shouldContinue: { false }) == nil,
                     "cancelling a scan preserves the last snapshot")
        let copy = folder.appending(path: "copied.db")
        execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try FileManager.default.copyItem(at: file, to: copy)
        let copied = reader.read(roots: [folder], since: horizon, now: now.addingTimeInterval(33)) ?? []
        suite.expect(copied.count == 2, "copied conversation databases cannot double-count request identities")
        let unknown = bytes(1, bytes(4, usage(7, request: "unknown", model: 999999)))
        execute("INSERT INTO gen_metadata VALUES (2, \(hex(unknown)))")
        let withUnknown = reader.read(roots: [folder], since: horizon, now: now.addingTimeInterval(44)) ?? []
        suite.expect(withUnknown.contains { $0.record.model == "antigravity-model-999999" && $0.record.cost == nil },
                     "unknown models retain tokens and stay unpriced instead of fabricating cost")
        let store = AgentUsageStore()
        let codex = AgentUsageRecord(provider: .codex, date: now, model: "gpt-6-luna", project: "", session: "other",
                                     tokens: AgentTokens(input: 1), cost: 0, savings: 0)
        store.apply([.usage(key: "codex:test", record: codex, billable: AgentBillable(tokens: codex.tokens))],
                    file: "codex", provider: .codex, tracksTurns: false, modified: now)
        store.replaceAntigravityUsage(first)
        store.replaceAntigravityUsage(updated)
        suite.expect(store.records.count == 3 && store.records.filter { $0.provider == .antigravity }.reduce(0) { $0 + $1.tokens.input } == 205,
                     "database snapshots replace stale usage instead of adding on top of it")
        store.apply([.usage(key: "codex:test", record: codex, billable: AgentBillable(tokens: codex.tokens))],
                    file: "codex", provider: .codex, tracksTurns: false, modified: now)
        suite.expect(store.records.count == 3, "replacing Antigravity preserves other providers' deduplication indices")
        store.replaceAntigravityUsage([])
        suite.expect(store.records == [codex], "deleted database usage is removed without deleting another provider's usage")
    }
}
