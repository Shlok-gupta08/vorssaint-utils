// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Live state comes from the running local server, not display transcripts:
/// modern Antigravity can leave those unchanged for an entire task.
final class AgentAntigravityActivity {
    struct Endpoint: Equatable {
        let pid: Int32
        let port: Int
        let token: String
    }

    private let queue: DispatchQueue
    private let changed: ([AgentLiveSession]) -> Void
    private let limitsChanged: ((AgentLimits) -> Void)?
    private let planChanged: ((AgentPlan) -> Void)?
    private let session: URLSession
    private var timer: DispatchSourceTimer?
    private var endpoints: [Endpoint] = []
    private var hasT3Adapter = false
    private var lastDiscovery = Date.distantPast
    private var lastLimitsPoll = Date.distantPast
    private var lastStatusPoll = Date.distantPast
    private var generation = 0
    private var inFlight = false
    private var limitsInFlight = false
    private var stopped = false
    private var previous: [AgentLiveSession] = []
    private var previousLimitsByKey: [String: AgentLimits] = [:]
    private var previousPlan: AgentPlan?
    private var cloudQuota: AgentAntigravityQuota?

    init(queue: DispatchQueue,
         changed: @escaping ([AgentLiveSession]) -> Void,
         limitsChanged: ((AgentLimits) -> Void)? = nil,
         planChanged: ((AgentPlan) -> Void)? = nil) {
        self.queue = queue
        self.changed = changed
        self.limitsChanged = limitsChanged
        self.planChanged = planChanged
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 3
        config.connectionProxyDictionary = [:]
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        stopped = true
        cloudQuota?.stop(); cloudQuota = nil
        generation += 1
        timer?.cancel()
        timer = nil
        session.invalidateAndCancel()
    }

    deinit { timer?.cancel(); session.invalidateAndCancel() }

    /// Parses process arguments without retaining or logging the command
    /// line. The CSRF value stays in memory and is sent only to loopback.
    static func endpoint(pid: Int32, arguments: [String]) -> Endpoint? {
        guard let executable = arguments.first else { return nil }
        let name = URL(fileURLWithPath: executable).lastPathComponent
        guard name == "agy" || name.hasPrefix("language_server_macos") else { return nil }
        func flag(_ name: String) -> String? {
            for (index, value) in arguments.enumerated() {
                if value.hasPrefix(name + "=") { return String(value.dropFirst(name.count + 1)) }
                if value == name, arguments.indices.contains(index + 1) { return arguments[index + 1] }
            }
            return nil
        }
        guard let token = flag("--csrf_token"), !token.isEmpty,
              let rawPort = flag("--hub-port") ?? flag("--server_port"),
              let port = Int(rawPort), (1...65535).contains(port) else { return nil }
        return Endpoint(pid: pid, port: port, token: token)
    }

    /// T3 ships both the legacy Python adapter and the newer native binary.
    /// Keep the tool-directory check so an unrelated process cannot enable it.
    static func isT3Adapter(executable: String) -> Bool {
        guard executable.contains("/.t3/tools/antigravity-acp/") else { return false }
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return name == "agy_acp_server.par" || name == "antigravity"
    }

    private static func discover() -> (endpoints: [Endpoint], t3: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ([], false) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return ([], false) }
        var t3 = false
        let endpoints: [Endpoint] = text.split(separator: "\n").compactMap { line in
            // Only inspect agent server processes, never shell command text.
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2, let pid = Int32(parts[0]) else { return nil }
            if isT3Adapter(executable: parts[1]) { t3 = true }
            return endpoint(pid: pid, arguments: Array(parts.dropFirst()))
        }
        return (endpoints, t3)
    }

    /// Only status, timestamps, ids and workspace folder names survive the
    /// response. Titles, previews, prompts and replies are never retained.
    static func live(_ data: Data, endpoint: Endpoint, now: Date) -> [AgentLiveSession]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let summaries = json["trajectorySummaries"] as? [String: [String: Any]] else { return nil }
        return summaries.compactMap { id, value in
            let status = value["status"] as? String ?? ""
            guard ["CASCADE_RUN_STATUS_RUNNING", "CASCADE_RUN_STATUS_BUSY"].contains(status),
                  value["killed"] as? Bool != true else { return nil }
            let started = AgentLogParser.timestamp(value["lastUserInputTime"])
                ?? AgentLogParser.timestamp(value["createdTime"]) ?? now
            let workspaces = value["workspaces"] as? [[String: Any]] ?? []
            let uri = workspaces.first?["workspaceFolderAbsoluteUri"] as? String ?? ""
            let project = URL(string: uri).map { AgentLogParser.projectName($0.path) } ?? ""
            return AgentLiveSession(id: "antigravity-live:\(endpoint.pid):\(id)", provider: .antigravity,
                                    started: min(started, now), lastActivity: now, model: "", project: project,
                                    tokens: AgentTokens(), cost: 0)
        }.sorted { $0.id < $1.id }
    }

    /// Quota buckets and reset windows from RetrieveUserQuotaSummary.
    static func limits(_ data: Data, observed: Date) -> AgentLimits? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let response = (json["response"] as? [String: Any]) ?? json
        let groups = response["groups"] as? [[String: Any]] ?? [["buckets": response["buckets"] ?? []]]
        var windows: [AgentLimitWindow] = []
        for group in groups {
            let groupName = group["displayName"] as? String ?? ""
            // Only track Gemini models: ignore Claude, GPT, and 3rd-party models.
            let buckets = group["buckets"] as? [[String: Any]] ?? []
            for bucket in buckets {
                let bucketId = bucket["bucketId"] as? String ?? ""
                guard groupName.localizedCaseInsensitiveContains("gemini") || bucketId.hasPrefix("gemini-"),
                      let number = bucket["remainingFraction"] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { continue }
                let rawWindow = bucket["window"] as? String ?? ""
                let remainingFraction = number.doubleValue
                let usedPercent = min(100.0, max(0.0, (1.0 - remainingFraction) * 100.0))
                let resetsAt = (bucket["resetTime"] as? String).flatMap(AgentTimestamp.parse)

                let kind: AgentLimitWindow.Kind
                let minutes: Int?
                if rawWindow == "5h" {
                    kind = .session
                    minutes = 300
                } else if rawWindow == "weekly" {
                    kind = .weekly
                    minutes = 10080
                } else {
                    kind = .other
                    minutes = nil
                }

                let windowId = "antigravity.\(bucketId.isEmpty ? rawWindow : bucketId)"
                windows.append(AgentLimitWindow(
                    id: windowId,
                    kind: kind,
                    minutes: minutes,
                    scope: nil,
                    usedPercent: usedPercent,
                    resetsAt: resetsAt,
                    disabled: bucket["disabled"] as? Bool == true
                ))
            }
        }
        guard !windows.isEmpty else { return nil }
        windows.sort { ($0.minutes ?? .max) < ($1.minutes ?? .max) }
        return AgentLimits(provider: .antigravity, windows: windows, observedAt: observed, source: .account)
    }

    /// User subscription tier from GetUserStatus.
    static func plan(_ data: Data) -> AgentPlan? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let userTier = json["userTier"] as? [String: Any],
              let name = userTier["name"] as? String, !name.isEmpty else { return nil }
        return AgentPlan(name: name, monthlyPrice: nil)
    }

    func refreshLimits() {
        lastLimitsPoll = .distantPast
        cloudQuota?.poll(now: Date(), force: true)
        poll()
    }

    private func poll() {
        guard !stopped, !inFlight else { return }
        let now = Date()
        if now.timeIntervalSince(lastDiscovery) >= (endpoints.isEmpty && !hasT3Adapter ? 2 : 5) {
            let found = Self.discover()
            endpoints = found.endpoints
            hasT3Adapter = found.t3
            lastDiscovery = now
        }
        if let primary = endpoints.first, !limitsInFlight,
           (lastLimitsPoll == .distantPast || now.timeIntervalSince(lastLimitsPoll) >= 15) {
            pollLimits(endpoint: primary, now: now)
        }
        // Always poll cloud quotas for all signed-in T3 / standalone Antigravity accounts.
        pollCloudQuota(now: now)
        // Always read T3 SQLite directly when present so multi-instance providers
        // (e.g. antigravity_antigravity_2, codex_*, claude_*) are always detected
        // regardless of adapter binary path changes.
        var live = AgentT3AntigravityReader.read(now: now)
        guard !endpoints.isEmpty else { deliver(live); return }
        inFlight = true
        let generation = generation
        var remaining = endpoints.count
        for endpoint in endpoints {
            let url = URL(string: "http://127.0.0.1:\(endpoint.port)/exa.language_server_pb.LanguageServerService/GetAllCascadeTrajectories")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data("{\"excludeSubtrajectories\":true}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(endpoint.token, forHTTPHeaderField: "X-Codeium-Csrf-Token")
            session.dataTask(with: request) { [weak self] data, response, _ in
                guard let self else { return }
                let reading = (response as? HTTPURLResponse)?.statusCode == 200
                    ? data.flatMap { Self.live($0, endpoint: endpoint, now: now) } : nil
                self.queue.async { [weak self] in
                    guard let self, !self.stopped, self.generation == generation else { return }
                    live.append(contentsOf: reading ?? [])
                    remaining -= 1
                    if remaining == 0 {
                        self.inFlight = false
                        self.deliver(live.sorted { $0.id < $1.id })
                    }
                }
            }.resume()
        }
    }

    private func pollLimits(endpoint: Endpoint, now: Date) {
        guard !limitsInFlight else { return }
        limitsInFlight = true
        lastLimitsPoll = now
        let quotaURL = URL(string: "http://127.0.0.1:\(endpoint.port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")!
        var quotaReq = URLRequest(url: quotaURL)
        quotaReq.httpMethod = "POST"
        quotaReq.httpBody = Data("{}".utf8)
        quotaReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        quotaReq.setValue(endpoint.token, forHTTPHeaderField: "X-Codeium-Csrf-Token")

        let generation = generation
        session.dataTask(with: quotaReq) { [weak self] data, response, _ in
            guard let self else { return }
            let reading = (response as? HTTPURLResponse)?.statusCode == 200
                ? data.flatMap { Self.limits($0, observed: now) } : nil
            self.queue.async { [weak self] in
                guard let self, !self.stopped, self.generation == generation else { return }
                self.limitsInFlight = false
                if let reading { self.deliverLimits(reading) }
                // Always poll per-account cloud quotas as well so secondary T3 Antigravity
                // accounts (e.g. Antigravity 2) fetch their own independent quota instead of
                // being shadowed by a single local IDE hub.
                self.pollCloudQuota(now: now)
            }
        }.resume()

        if previousPlan == nil || now.timeIntervalSince(lastStatusPoll) >= 300 {
            lastStatusPoll = now
            let statusURL = URL(string: "http://127.0.0.1:\(endpoint.port)/exa.language_server_pb.LanguageServerService/GetUserStatus")!
            var statusReq = URLRequest(url: statusURL)
            statusReq.httpMethod = "POST"
            statusReq.httpBody = Data("{}".utf8)
            statusReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            statusReq.setValue(endpoint.token, forHTTPHeaderField: "X-Codeium-Csrf-Token")

            session.dataTask(with: statusReq) { [weak self] data, response, _ in
                guard let self else { return }
                let plan = (response as? HTTPURLResponse)?.statusCode == 200
                    ? data.flatMap { Self.plan($0) } : nil
                self.queue.async { [weak self] in
                    guard let self, !self.stopped, self.generation == generation else { return }
                    if let plan, plan != self.previousPlan {
                        self.previousPlan = plan
                        self.planChanged?(plan)
                    }
                }
            }.resume()
        }
    }

    private func pollCloudQuota(now: Date) {
        if cloudQuota == nil {
            cloudQuota = AgentAntigravityQuota(queue: queue) { [weak self] in self?.deliverLimits($0) }
        }
        cloudQuota?.poll(now: now)
    }

    private func deliverLimits(_ limits: AgentLimits) {
        let key = limits.accountID ?? limits.provider.rawValue
        let previous = previousLimitsByKey[key]
        guard previous?.windows != limits.windows
            || limits.observedAt.timeIntervalSince(previous?.observedAt ?? .distantPast) >= 60 else { return }
        previousLimitsByKey[key] = limits
        limitsChanged?(limits)
    }

    private func deliver(_ live: [AgentLiveSession]) {
        // A heartbeat confirms a long task is still running, but elapsed
        // time is rendered by the existing clock, without republishing here.
        guard previous.map(\.id) != live.map(\.id)
                || zip(previous, live).contains(where: {
                    $0.started != $1.started || $0.project != $1.project || $0.accountLabel != $1.accountLabel
                }) else { return }
        previous = live
        changed(live)
    }
}

/// T3's ACP adapter bypasses the standalone Antigravity server and its logs.
/// Read only the durable run status and workspace/model metadata across ALL
/// T3 provider instances (including multi-account instances like `antigravity_antigravity_2`,
/// `codex_*`, and `claude_*`), never messages, prompts, or credentials.
enum AgentT3AntigravityReader {
    static func read(database: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".t3/userdata/statev2.sqlite"), now: Date) -> [AgentLiveSession] {
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(db, 100)
        let query = """
        SELECT r.run_id,
               r.provider,
               COALESCE(n.started_at, r.requested_at),
               COALESCE(json_extract(r.payload_json, '$.modelSelection.model'), ''),
               COALESCE(json_extract(t.payload_json, '$.worktreePath'), p.workspace_root, ''),
               COALESCE(json_extract(r.payload_json, '$.modelSelection.instanceId'), r.provider, '')
        FROM orchestration_v2_projection_runs r
        JOIN orchestration_v2_projection_threads t ON t.thread_id = r.thread_id
        JOIN orchestration_v2_projection_nodes n ON n.node_id = json_extract(r.payload_json, '$.rootNodeId')
        LEFT JOIN projection_projects p ON p.project_id = t.project_id
        WHERE r.status = 'running' AND r.completed_at IS NULL
          AND n.status = 'running' AND n.completed_at IS NULL AND t.deleted_at IS NULL
        ORDER BY r.run_id
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        func text(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
        let configuredAccounts = AgentAccountRegistry.accounts()
        var live: [AgentLiveSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rawProvider = text(1)
            let instanceID = text(5).isEmpty ? rawProvider : text(5)
            guard let provider = AgentAccountRegistry.provider(forT3Name: rawProvider)
                    ?? AgentAccountRegistry.provider(forT3Name: instanceID) else { continue }
            // Skip runs whose specific T3 account was explicitly disabled by the user.
            let matchedAccount = configuredAccounts.first { $0.t3InstanceID == instanceID }
            if let matchedAccount, !matchedAccount.enabled { continue }
            guard let started = AgentTimestamp.parse(text(2)), started <= now.addingTimeInterval(60) else { continue }
            let accountLabel = matchedAccount?.label ?? (instanceID == provider.rawValue ? nil : instanceID)
            live.append(AgentLiveSession(
                id: "t3-live:\(text(0))",
                provider: provider,
                started: min(started, now),
                lastActivity: now,
                model: text(3),
                project: AgentLogParser.projectName(text(4)),
                tokens: AgentTokens(),
                cost: 0,
                accountID: matchedAccount?.id ?? "t3:\(provider.rawValue):\(instanceID)",
                accountLabel: accountLabel
            ))
        }
        return live
    }
}
