// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

typealias AgentUsageProductionLogReader = AgentLogReader

/// Runs the service's production read method, parser, cursor and store. The
/// reader wrapper only observes when a complete line is handed to the service.
enum AgentUsageReadTests {
    enum AgentLogReader {
        static var beforeLine: (() -> Void)?
        static func readAppended(_ cursor: AgentLogCursor, since horizon: Date, shouldContinue: () -> Bool,
                                 line: (Data) -> Void) {
            AgentUsageProductionLogReader.readAppended(cursor, since: horizon, shouldContinue: shouldContinue) {
                beforeLine?()
                line($0)
            }
        }
    }

    final class Cancellation {
        var isCancelled = false
    }

    class Fixture {
        static let horizon = TimeInterval(AgentUsageSnapshot.dayCount) * 86_400
        var readerCancellation: Cancellation? = Cancellation()
        var cursors: [String: AgentLogCursor] = [:]
        let store = AgentUsageStore()
        var events: [AgentUsageEvent] = []
        func report(_ event: AgentUsageEvent) { events.append(event) }
    }

    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-streaming-\(UUID().uuidString)")
        defer {
            AgentLogReader.beforeLine = nil
            try? FileManager.default.removeItem(at: folder)
        }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { suite.expect(false, "the streaming fixture creates its folder: \(error)"); return }
        let now = Date()
        let timestamp = now.timeIntervalSince1970
        let cases: [(AgentProvider, [String])] = [
            (.claude, [
                #"{"type":"user","timestamp":\#(timestamp),"sessionId":"s","message":{"content":"work"}}"#,
                #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":2}}}"#,
                #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5}}}"#,
                #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r2","message":{"id":"m2","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":7}}}"#
            ]),
            (.codex, [
                #"{"type":"session_meta","timestamp":\#(timestamp),"payload":{"id":"s","cwd":"/tmp/example"}}"#,
                #"{"type":"turn_context","timestamp":\#(timestamp),"payload":{"model":"gpt-5.2-codex"}}"#,
                #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"task_started"}}"#,
                #"{"type":"token_usage_record","timestamp":\#(timestamp),"payload":{"response_id":"r","usage":{"input_tokens":10,"output_tokens":2}}}"#,
                #"{"type":"token_usage_record","timestamp":\#(timestamp),"payload":{"response_id":"r","usage":{"input_tokens":10,"output_tokens":5}}}"#,
                #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"token_count","rate_limits":{"plan_type":"pro","primary":{"used_percent":42,"window_minutes":300}}}}"#,
                #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"task_complete","duration_ms":20000}}"#
            ])
        ]
        for (provider, lines) in cases {
            // A canonical filename, not a Codex side-thread filename.
            let file = folder.appending(path: "\(provider.rawValue).jsonl")
            do { try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file) }
            catch { suite.expect(false, "the streaming fixture writes its log: \(error)"); continue }

            let cursor = AgentLogCursor(path: file.path, provider: provider)
            var entries: [AgentLogEntry] = []
            AgentUsageProductionLogReader.readAppended(cursor) { line in
                switch provider {
                case .claude: entries += AgentLogParser.parseClaude(line, state: &cursor.state, now: now)
                case .codex: entries += AgentLogParser.parseCodex(line, state: &cursor.state, now: now)
                case .antigravity: entries += AgentLogParser.parseAntigravity(line, state: &cursor.state, now: now)
                case .opencode: entries += AgentLogParser.parseOpenCode(line, state: &cursor.state, now: now)
                }
            }
            let reference = AgentUsageStore()
            reference.reportsTransitions = true
            let expectedEvents = reference.apply(entries, file: file.path, provider: provider,
                                                 tracksTurns: cursor.tracksTurns, parent: cursor.parent,
                                                 modified: cursor.modified, now: now)
            let host = Host()
            host.store.reportsTransitions = true
            var counts: [Int] = []
            AgentLogReader.beforeLine = { counts.append(host.store.records.count) }
            suite.expect(host.read(file.path, provider: provider), "a \(provider.rawValue) log reports parsed entries")
            AgentLogReader.beforeLine = nil
            suite.expect(counts.contains(where: { $0 > 0 }),
                         "\(provider.rawValue) records are applied before the rest of the log is read")
            suite.expect(host.store.records == reference.records && host.store.turns == reference.turns
                            && host.store.waiting == reference.waiting && host.store.limits == reference.limits
                            && host.store.codexPlan == reference.codexPlan && host.events == expectedEvents,
                         "streaming \(provider.rawValue) preserves duplicate merging, usage, turns, limits, plans and event order")
            suite.expect(!expectedEvents.isEmpty && host.cursors[file.path]?.state == cursor.state,
                         "\(provider.rawValue) finishes the same turn and retains the same parser context")
            suite.expect(!host.read(file.path, provider: provider) && host.events == expectedEvents,
                         "an unchanged \(provider.rawValue) file neither changes the store nor replays events")
            host.readerCancellation?.isCancelled = true
            suite.expect(!host.read(file.path, provider: provider), "a cancelled reading consumes no more entries")
        }
        do {
            let root = folder.appending(path: ".gemini/antigravity-ide/brain")
            let logs = root.appending(path: "session/.system_generated/logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let file = logs.appending(path: "transcript.jsonl")
            func transcript(_ status: String) -> Data {
                let user = #"{"step_index":0,"type":"USER_INPUT","status":"DONE","source":"USER_EXPLICIT","created_at":\#(timestamp)}"#
                let response = #"{"step_index":1,"type":"PLANNER_RESPONSE","status":"\#(status)","source":"MODEL","created_at":\#(timestamp),"tool_calls":[],"output_tokens":8}"#
                return Data((user + "\n" + response.padding(toLength: 256, withPad: " ", startingAt: 0) + "\n").utf8)
            }
            try transcript("RUNNING").write(to: file)
            try transcript("DONE").write(to: logs.appending(path: "transcript_full.jsonl"))
            let found = AgentUsageProductionLogReader.discover([AgentLogRoot(provider: .antigravity, url: root)], since: .distantPast)
            suite.expect(found.count == 1 && found.first?.path.hasSuffix("/session/.system_generated/logs/transcript.jsonl") == true,
                         "Antigravity reads its display transcript once and skips full copies")
            let host = Host()
            host.store.reportsTransitions = true
            suite.expect(host.read(file.path, provider: .antigravity) && host.store.live.count == 1,
                         "the production reader detects Antigravity working")
            let size = try Data(contentsOf: file).count
            try transcript("DONE").write(to: file)
            suite.expect(try Data(contentsOf: file).count == size, "the Antigravity rewrite fixture keeps the same size")
            suite.expect(host.read(file.path, provider: .antigravity) && host.store.live.isEmpty && host.events.count == 1,
                         "same-size transcript status rewrites end work and emit one completion")
            suite.expect(!host.read(file.path, provider: .antigravity) && host.events.count == 1,
                         "unchanged Antigravity transcripts never replay completion alerts")
        } catch { suite.expect(false, "Antigravity transcript fixtures: \(error)") }
    }
}
