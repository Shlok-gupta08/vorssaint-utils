// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3
import Darwin

/// Current Antigravity stores usage in conversation SQLite metadata, not its
/// display transcripts. Read only generation/step metadata, never step payloads,
/// messages, credentials or the conversation search index. Confined to the usage queue.
final class AgentAntigravityUsageReader {
    struct Entry {
        let key: String
        let record: AgentUsageRecord
        let billable: AgentBillable
    }

    private struct Candidate {
        var keys: [String]
        var session: String
        var model: String
        var modelID: Int
        var quality: Int
        var date: Date
        var timeQuality: Int
        var tokens: AgentTokens
    }
    private struct Cached {
        let fingerprint: String
        let candidates: [Candidate]
    }
    private var cache: [String: Cached] = [:]
    private var published: [String: String] = [:]
    private var scanned = Date.distantPast
    private(set) var hasDatabases = false

    func reset() {
        cache.removeAll()
        published.removeAll()
        scanned = .distantPast
        hasDatabases = false
    }

    static func roots(home: URL) -> [URL] {
        var roots = ["antigravity", "antigravity-ide", "antigravity-cli", "antigravity-backup"]
            .map { home.appending(path: ".gemini/\($0)/conversations") }
        roots.append(home.appending(path: ".config/antigravity/conversations"))
        let profiles = home.appending(path: ".t3/userdata/providers/antigravity")
        for profile in (try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil)) ?? [] {
            roots.append(profile.appending(path: "antigravity-acp/conversations"))
        }
        // Also pool any user-added custom Antigravity account directories.
        for account in AgentAccountRegistry.enabledAccounts(for: .antigravity, home: home) where !account.isAutoDiscovered && !account.sourcePath.isEmpty {
            let base = account.expandedURL
            roots.append(base.appending(path: "conversations"))
            roots.append(base.appending(path: "antigravity-acp/conversations"))
        }
        return roots
    }

    /// nil means unchanged, cancelled or temporarily unreadable; keep the last
    /// good snapshot. Fingerprint WAL as well: new usage need not touch the DB.
    func read(roots: [URL], since horizon: Date, now: Date = Date(), force: Bool = false,
              shouldContinue: () -> Bool = { true }) -> [Entry]? {
        guard force || now.timeIntervalSince(scanned) >= 10 else { return nil }
        guard shouldContinue() else { return nil }
        scanned = now
        var paths = Set<String>()
        var complete = true
        for root in Set(roots.map { $0.resolvingSymlinksInPath() }) where FileManager.default.fileExists(atPath: root.path) {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants], errorHandler: { _, _ in complete = false; return false }) else {
                complete = false
                continue
            }
            for case let url as URL in walker {
                guard shouldContinue() else { return nil }
                if url.pathExtension == "db", (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    paths.insert(url.resolvingSymlinksInPath().path)
                }
            }
        }
        guard complete else { return nil }
        for path in paths.sorted() {
            guard shouldContinue() else { return nil }
            let mark = Self.fingerprint(path)
            if cache[path]?.fingerprint == mark { continue }
            if let candidates = Self.readDatabase(path, shouldContinue: shouldContinue), shouldContinue() {
                // A write during the read must be picked up on the next scan.
                cache[path] = Cached(fingerprint: Self.fingerprint(path) == mark ? mark : "retry", candidates: candidates)
            }
        }
        guard shouldContinue() else { return nil }
        cache = cache.filter { paths.contains($0.key) }
        hasDatabases = !cache.isEmpty
        let marks = cache.mapValues(\.fingerprint)
        guard !cache.isEmpty || !published.isEmpty else { return nil }
        guard marks != published || force else { return nil }
        published = marks
        return Self.entries(cache.keys.sorted().flatMap { cache[$0]!.candidates }, since: horizon, now: now)
    }

    private static func fingerprint(_ path: String) -> String {
        [path, path + "-wal"].map { part in
            var info = stat()
            guard stat(part, &info) == 0 else { return "-" }
            return "\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
        }.joined(separator: "/")
    }

    private static func readDatabase(_ path: String, shouldContinue: () -> Bool) -> [Candidate]? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 100)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        var tables: OpaquePointer?
        defer { sqlite3_finalize(tables) }
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table'", -1, &tables, nil) == SQLITE_OK else { return nil }
        var names = Set<String>()
        while sqlite3_step(tables) == SQLITE_ROW {
            if let name = sqlite3_column_text(tables, 0) { names.insert(String(cString: name)) }
        }
        guard names.contains("gen_metadata") || names.contains("steps") else { return nil }
        let session = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        var fallback = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date ?? .distantPast
        var timeQuality = 0
        if names.contains("trajectory_metadata_blob") {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            if sqlite3_prepare_v2(db, "SELECT data FROM trajectory_metadata_blob LIMIT 1", -1, &statement, nil) == SQLITE_OK,
               sqlite3_step(statement) == SQLITE_ROW, let data = blob(statement, 0),
               let root = try? Proto(data, keeping: [2]), let date = root.nested(2).date {
                fallback = date
                timeQuality = 1
            }
        }
        var result: [Candidate] = []
        var generationCandidates: [Candidate] = []
        var generationModels: [Int64: (id: Int, name: String)] = [:]
        for step in [false, true] where names.contains(step ? "steps" : "gen_metadata") {
            var statement: OpaquePointer?
            let query = step ? "SELECT idx, metadata FROM steps ORDER BY idx" : "SELECT idx, data FROM gen_metadata ORDER BY idx"
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                guard shouldContinue() else { return nil }
                let index = sqlite3_column_int64(statement, 0)
                if let bytes = blob(statement, 1),
                   let root = try? Proto(bytes, keeping: step ? [1, 8, 9, 24, 28] : [1]) {
                    let data = step ? root : root.nested(1, keeping: [3, 4, 9, 17, 19, 21])
                    let model = step ? data.nested(24, keeping: [1, 8, 12]) : data
                    let modelID = model.number(step ? 1 : 3)
                    let labels = [model.text(step ? 12 : 19), model.text(step ? 8 : 21)].map(normalizedModel)
                    let label = labels.first(where: concreteModel) ?? labels.first(where: { !$0.isEmpty && !$0.hasPrefix("model_") }) ?? ""
                    if !step { generationModels[index] = (modelID, label) }
                    let date = step ? (data.nested(8).date ?? data.nested(1).date) : data.nested(9).nested(4).date
                    var usages = data.bytes(step ? 9 : 4).compactMap { try? Proto($0) }
                    for retry in data.bytes(step ? 28 : 17) {
                        if let retry = try? Proto(retry) { usages += retry.bytes(2).compactMap { try? Proto($0) } }
                    }
                    for (usageIndex, usage) in usages.enumerated() {
                        let usageModelID = usage.number(1)
                        var usageLabel = usageModelID == 0 || usageModelID == modelID ? label : ""
                        if usageLabel.isEmpty, step, let generation = generationModels[index],
                           usageModelID == 0 || usageModelID == generation.id { usageLabel = generation.name }
                        let output = max(usage.number(3), usage.number(9) + usage.number(10))
                        let tokens = AgentTokens(input: usage.number(2), cacheWrite: usage.number(4),
                            cacheRead: usage.number(5), output: output, reasoning: min(output, usage.number(9)))
                        guard tokens.total > 0 else { continue }
                        let keys = [11, 12, 7].compactMap { field -> String? in
                            let id = usage.text(field)
                            return id.isEmpty ? nil : "antigravity-db:\(field):\(id)"
                        }
                        result.append(Candidate(keys: keys.isEmpty ? ["antigravity-db:\(session):\(step ? "step" : "generation"):\(index):\(usageIndex)"] : keys,
                            session: session, model: usageLabel, modelID: usageModelID == 0 ? modelID : usageModelID,
                            quality: concreteModel(usageLabel) ? 4 : (usageLabel.isEmpty ? 0 : 1), date: date ?? fallback,
                            timeQuality: date == nil ? timeQuality : 2, tokens: tokens))
                    }
                }
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else { return nil }
            if !step { generationCandidates = result; result = [] }
        }
        // The step is the authoritative copy when two equally precise model
        // labels disagree; generation metadata supplies missing names/counters.
        return result + generationCandidates
    }

    private static func blob(_ statement: OpaquePointer?, _ column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, count <= 32 << 20, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private static func normalizedModel(_ name: String) -> String {
        var model = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        model = model.replacingOccurrences(of: #"\s*\(([^)]*)\)\s*$"#, with: "-$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        if model.hasPrefix("claude-") {
            model = model.replacingOccurrences(of: #"^claude-(\d+(?:\.\d+)?)-(sonnet|opus|haiku)"#, with: "claude-$2-$1", options: .regularExpression)
                .replacingOccurrences(of: ".", with: "-")
        }
        return model
    }

    private static func concreteModel(_ model: String) -> Bool {
        model.range(of: #"^(gemini-\d|claude-(sonnet|opus|haiku)-\d|gpt-)"#, options: .regularExpression) != nil
            && model.range(of: #"^gemini-3-flash-(agent(-[ab])?|[ab])$"#, options: .regularExpression) == nil
    }

    /// Request aliases can connect a generation, its step, retries and copied
    /// databases. Merge the whole connected group once, taking cumulative maxima.
    private static func entries(_ candidates: [Candidate], since horizon: Date, now: Date) -> [Entry] {
        var learned: [Int: Set<String>] = [:]
        for c in candidates where c.modelID > 0 && concreteModel(c.model) { learned[c.modelID, default: []].insert(c.model) }
        var groups: [Candidate] = []
        var parents: [Int] = []
        var identities: [String: Int] = [:]
        func root(_ id: Int) -> Int {
            var current = id
            while parents[current] != current { current = parents[current] }
            return current
        }
        for var c in candidates {
            if c.quality < 4 {
                if let models = learned[c.modelID], models.count == 1, let model = models.first {
                    c.model = model; c.quality = 3
                } else if learned[c.modelID] == nil, let model = modelIDs[c.modelID] {
                    c.model = model; c.quality = 2
                }
            }
            if c.model.isEmpty { c.model = c.modelID == 0 ? "antigravity-unknown" : "antigravity-model-\(c.modelID)" }
            let id = groups.count
            groups.append(c); parents.append(id)
            for key in c.keys {
                if let existing = identities[key] {
                    let a = root(id), b = root(existing)
                    if a != b {
                        let target = min(a, b), source = max(a, b)
                        let other = groups[source]
                        groups[target].tokens = groups[target].tokens.merged(with: other.tokens)
                        if other.quality > groups[target].quality { groups[target].model = other.model; groups[target].quality = other.quality }
                        if other.timeQuality > groups[target].timeQuality || (other.timeQuality == groups[target].timeQuality && other.date < groups[target].date) {
                            groups[target].date = other.date; groups[target].timeQuality = other.timeQuality
                        }
                        groups[target].keys += other.keys
                        parents[source] = target
                    }
                }
                identities[key] = id
            }
        }
        return groups.indices.compactMap { id in
            let c = groups[id]
            guard root(id) == id, c.date >= horizon, c.date <= now.addingTimeInterval(60) else { return nil }
            let billable = AgentBillable(tokens: c.tokens)
            let priced = AgentPricing.cost(billable, model: c.model)
            return Entry(key: c.keys.min()!, record: AgentUsageRecord(provider: .antigravity, date: c.date,
                model: c.model, project: "", session: c.session, tokens: c.tokens, cost: priced.cost, savings: priced.savings), billable: billable)
        }
    }

    // Numeric IDs are a fallback only; concrete model metadata wins. Unknown IDs
    // retain their counters and remain unpriced rather than borrowing a model.
    private static let modelIDs: [Int: String] = [
        246: "gemini-2.5-pro", 312: "gemini-2.5-flash", 313: "gemini-2.5-flash-thinking", 329: "gemini-2.5-flash-thinking",
        330: "gemini-2.5-flash-lite", 281: "claude-sonnet-4", 282: "claude-sonnet-4", 290: "claude-opus-4", 291: "claude-opus-4",
        333: "claude-sonnet-4-5", 334: "claude-sonnet-4-5", 340: "claude-haiku-4-5", 341: "claude-haiku-4-5", 342: "gpt-oss-120b-medium",
        1026: "claude-opus-4-6", 1035: "claude-sonnet-4-6", 1016: "gemini-3.1-pro", 1036: "gemini-3.1-pro", 1037: "gemini-3.1-pro",
        1018: "gemini-3-flash-preview", 1084: "gemini-3-flash-preview", 1047: "gemini-3-flash-preview",
        1020: "gemini-3.5-flash-medium", 1021: "gemini-3.1-flash-image", 1050: "gemini-3.1-flash-lite",
        1071: "gemini-3.6-flash-high", 1072: "gemini-3.6-flash-medium", 1073: "gemini-3.6-flash-low",
        1132: "gemini-3.5-flash-high", 1133: "gemini-3.5-flash-high", 1187: "gemini-3.5-flash-extra-low",
        1196: "gemini-3.6-flash", 1266: "gemini-3.6-flash", 1298: "gemini-3.7-flash-high", 1299: "gemini-3.7-flash-medium",
        1300: "gemini-3.7-flash-low", 1301: "gemini-3.7-flash-tiered", 1318: "gemini-3.8-flash-high",
        1319: "gemini-3.8-flash-medium", 1320: "gemini-3.8-flash-low", 1322: "gemini-3.8-flash-tiered",
        1402: "claude-opus-5-5", 1417: "gemini-4-argon", 1418: "gemini-4-argon", 1419: "gemini-4-argon",
    ]

    /// Bounded protobuf wire decoder. Unknown fields are skipped; only metadata
    /// fields requested by the caller are retained. No generated SDK required.
    private struct Proto {
        enum Value { case number(UInt64), bytes(Data) }
        enum Invalid: Error { case data }
        var fields: [Int: [Value]] = [:]
        init() {}
        init(_ data: Data, keeping: Set<Int>? = nil) throws {
            var offset = data.startIndex
            func varint() throws -> UInt64 {
                var result: UInt64 = 0
                for shift in stride(from: 0, through: 63, by: 7) {
                    guard offset < data.endIndex else { throw Invalid.data }
                    let byte = data[offset]; offset += 1
                    guard shift < 63 || byte <= 1 else { throw Invalid.data }
                    result |= UInt64(byte & 127) << shift
                    if byte < 128 { return result }
                }
                throw Invalid.data
            }
            while offset < data.endIndex {
                let tag = try varint(), field = tag >> 3
                guard field > 0, field <= UInt64(Int.max) else { throw Invalid.data }
                let key = Int(field), retain = keeping?.contains(key) ?? true
                switch tag & 7 {
                case 0:
                    let value = try varint()
                    if retain { fields[key, default: []].append(.number(value)) }
                case 1, 2, 5:
                    let length = tag & 7 == 2 ? try varint() : (tag & 7 == 1 ? 8 : 4)
                    guard length <= UInt64(data.endIndex - offset) else { throw Invalid.data }
                    let end = offset + Int(length)
                    if retain && tag & 7 == 2 { fields[key, default: []].append(.bytes(data.subdata(in: offset..<end))) }
                    offset = end
                default: throw Invalid.data
                }
            }
        }
        func number(_ key: Int) -> Int {
            guard case .number(let n)? = fields[key]?.first else { return 0 }
            return Int(min(n, 1_000_000_000_000))
        }
        func bytes(_ key: Int) -> [Data] { (fields[key] ?? []).compactMap { if case .bytes(let b) = $0 { return b }; return nil } }
        func nested(_ key: Int, keeping: Set<Int>? = nil) -> Proto { bytes(key).first.flatMap { try? Proto($0, keeping: keeping) } ?? Proto() }
        func text(_ key: Int) -> String { bytes(key).first.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        var date: Date? {
            let seconds = number(1)
            return seconds > 0 ? Date(timeIntervalSince1970: Double(seconds) + Double(number(2)) / 1_000_000_000) : nil
        }
    }
}
