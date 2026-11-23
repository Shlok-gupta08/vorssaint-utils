// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

private final class AgentQuotaRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Quotas remain available when the native ACP adapter has no local hub.
/// Supports multiple signed-in T3 Antigravity accounts and user-added custom
/// accounts independently without silently discarding multi-account setups.
final class AgentAntigravityQuota {
    struct CredentialSource: Equatable {
        let accountID: String
        let label: String
        let url: URL
    }

    struct Credential: Equatable {
        let clientID: String?
        let clientSecret: String?
        let refreshToken: String?
        let project: String?
        let accessToken: String?
        let expiry: Date?

        static func decode(_ data: Data) -> Credential? {
            guard data.count <= 65536,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            func text(_ key: String) -> String? {
                guard let value = json[key] as? String, !value.isEmpty else { return nil }
                return value
            }
            if let id = text("client_id"), let secret = text("client_secret"), let refresh = text("refresh_token") {
                return Credential(clientID: id, clientSecret: secret, refreshToken: refresh,
                    project: text("project_id"), accessToken: nil, expiry: nil)
            }
            guard let token = json["token"] as? [String: Any],
                  let access = token["access_token"] as? String, !access.isEmpty,
                  let rawExpiry = token["expiry"] as? String, let expiry = AgentTimestamp.parse(rawExpiry) else { return nil }
            return Credential(clientID: nil, clientSecret: nil, refreshToken: nil, project: nil,
                              accessToken: access, expiry: expiry)
        }
    }

    static func credentialURLs(home: URL) -> [URL] {
        credentialSources(home: home).map(\.url)
    }

    static func credentialSources(home: URL, defaults: UserDefaults = .standard) -> [CredentialSource] {
        let fm = FileManager.default
        var sources: [CredentialSource] = []
        var seenPaths = Set<String>()

        let configured = AgentAccountRegistry.enabledAccounts(for: .antigravity, in: defaults, home: home)
        for account in configured where !account.sourcePath.isEmpty {
            let base = account.expandedURL
            let candidates = [
                base.appending(path: "antigravity-oauth-token"),
                base.appending(path: "antigravity-acp/antigravity-oauth-token"),
                base.appending(path: "acp_token.json"),
                base.appending(path: "antigravity-acp/acp_token.json"),
                base.appending(path: "jetski-standalone-oauth-token"),
                base,
            ]
            if let match = candidates.first(where: {
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: $0.path, isDirectory: &isDir) && !isDir.boolValue
            }), seenPaths.insert(match.path).inserted {
                sources.append(CredentialSource(accountID: account.id, label: account.label, url: match))
            }
        }

        // Fallback if registry had no enabled disk paths yet
        if sources.isEmpty {
            let root = home.appending(path: ".t3/userdata/providers/antigravity")
            let profiles = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for (index, profile) in profiles.enumerated() {
                let oauthFile = profile.appending(path: "antigravity-acp/antigravity-oauth-token")
                let acpFile = profile.appending(path: "antigravity-acp/acp_token.json")
                let file = fm.fileExists(atPath: oauthFile.path) ? oauthFile : acpFile
                if fm.fileExists(atPath: file.path), seenPaths.insert(file.path).inserted {
                    let label = profiles.count == 1 ? "Antigravity" : "Antigravity \(index + 1)"
                    sources.append(CredentialSource(accountID: "t3:antigravity:\(profile.lastPathComponent)", label: label, url: file))
                }
            }
            let standalone = home.appending(path: ".gemini/jetski-standalone-oauth-token")
            if fm.fileExists(atPath: standalone.path), seenPaths.insert(standalone.path).inserted {
                sources.append(CredentialSource(accountID: "default:antigravity-standalone", label: "Antigravity", url: standalone))
            }
        }

        return sources
    }

    private struct TokenCache {
        var credential: Credential
        var access: String?
        var expires: Date = .distantPast
    }

    private struct CachedWindow: Codable {
        let id: String
        let kind: String
        let minutes: Int?
        let scope: String?
        let usedPercent: Double
        let resetsAt: Date?
        let disabled: Bool
    }

    private struct CachedAccountLimits: Codable {
        let accountID: String
        let accountLabel: String?
        let observedAt: Date
        let windows: [CachedWindow]
    }

    private static let quotaCacheDefaultsKey = "notchAgentsAntigravityQuotaCache"

    private let home: URL
    private let queue: DispatchQueue
    private let changed: (AgentLimits) -> Void
    private let session: URLSession
    private var stopped = false
    private var inFlightAccounts = Set<String>()
    private var lastPoll = Date.distantPast
    private var caches: [String: TokenCache] = [:]
    private var lastFileModified: [String: Date] = [:]
    private var hydratedCache = false

    init(queue: DispatchQueue, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         configuration: URLSessionConfiguration? = nil, changed: @escaping (AgentLimits) -> Void) {
        self.home = home; self.queue = queue; self.changed = changed
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: AgentQuotaRedirectPolicy(), delegateQueue: nil)
    }

    func stop() {
        stopped = true
        session.invalidateAndCancel()
        caches.removeAll()
        inFlightAccounts.removeAll()
    }

    deinit { session.invalidateAndCancel() }

    func poll(now: Date, force: Bool = false) {
        guard !stopped else { return }
        let sources = Self.credentialSources(home: home)
        if !hydratedCache {
            hydratedCache = true
            deliverCachedLimits(for: sources)
        }
        let anyFileChanged = sources.contains { source in
            guard let mtime = (try? source.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return false }
            return lastFileModified[source.accountID] != mtime
        }
        guard force || anyFileChanged || now.timeIntervalSince(lastPoll) >= 60 else { return }
        lastPoll = now
        for source in sources {
            if let mtime = (try? source.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                lastFileModified[source.accountID] = mtime
            }
            pollSource(source, now: now)
        }
    }

    private func deliverCachedLimits(for sources: [CredentialSource]) {
        guard let data = UserDefaults.standard.data(forKey: Self.quotaCacheDefaultsKey),
              let saved = try? JSONDecoder().decode([String: CachedAccountLimits].self, from: data) else { return }
        for source in sources {
            guard let entry = saved[source.accountID] else { continue }
            let windows = entry.windows.map {
                AgentLimitWindow(
                    id: $0.id,
                    kind: AgentLimitWindow.Kind(rawValue: $0.kind) ?? .other,
                    minutes: $0.minutes,
                    scope: $0.scope,
                    usedPercent: $0.usedPercent,
                    resetsAt: $0.resetsAt,
                    disabled: $0.disabled
                )
            }
            guard !windows.isEmpty else { continue }
            changed(AgentLimits(
                provider: .antigravity,
                windows: windows,
                observedAt: entry.observedAt,
                source: .account,
                accountID: source.accountID,
                accountLabel: source.label
            ))
        }
    }

    private func saveCachedLimits(_ limits: AgentLimits) {
        guard let accountID = limits.accountID else { return }
        var saved: [String: CachedAccountLimits] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.quotaCacheDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: CachedAccountLimits].self, from: data) {
            saved = decoded
        }
        saved[accountID] = CachedAccountLimits(
            accountID: accountID,
            accountLabel: limits.accountLabel,
            observedAt: limits.observedAt,
            windows: limits.windows.map {
                CachedWindow(
                    id: $0.id,
                    kind: $0.kind.rawValue,
                    minutes: $0.minutes,
                    scope: $0.scope,
                    usedPercent: $0.usedPercent,
                    resetsAt: $0.resetsAt,
                    disabled: $0.disabled
                )
            }
        )
        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: Self.quotaCacheDefaultsKey)
        }
    }

    private func pollSource(_ source: CredentialSource, now: Date) {
        guard !stopped, !inFlightAccounts.contains(source.accountID) else { return }
        guard let size = (try? source.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 65536,
              let data = try? Data(contentsOf: source.url), let next = Credential.decode(data) else { return }

        if caches[source.accountID]?.credential != next {
            caches[source.accountID] = TokenCache(credential: next)
        }
        inFlightAccounts.insert(source.accountID)

        if let cached = caches[source.accountID], let access = cached.access, cached.expires > now.addingTimeInterval(60) {
            fetch(access, project: next.project, source: source)
            return
        }
        if let access = next.accessToken, !access.isEmpty {
            if let expiry = next.expiry, expiry > now.addingTimeInterval(60) {
                caches[source.accountID]?.access = access
                caches[source.accountID]?.expires = expiry
                fetch(access, project: next.project, source: source)
                return
            }
            // If there is no client_id/client_secret to refresh locally, still attempt
            // the token once (Google may accept recently-expired tokens or return 401 cleanly).
            if next.clientID == nil || next.clientSecret == nil || next.refreshToken == nil {
                fetch(access, project: next.project, source: source)
                return
            }
        }
        guard let id = next.clientID, let secret = next.clientSecret, let refresh = next.refreshToken else {
            inFlightAccounts.remove(source.accountID)
            return
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "client_secret", value: secret),
            URLQueryItem(name: "refresh_token", value: refresh),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        session.dataTask(with: request) { [weak self] data, response, _ in
            self?.queue.async { [weak self] in
                guard let self, !self.stopped else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count <= 65536,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let access = json["access_token"] as? String, !access.isEmpty,
                      let duration = json["expires_in"] as? Double, duration > 0 else {
                    self.inFlightAccounts.remove(source.accountID)
                    return
                }
                self.caches[source.accountID]?.access = access
                self.caches[source.accountID]?.expires = Date().addingTimeInterval(duration)
                self.fetch(access, project: next.project, source: source)
            }
        }.resume()
    }

    private func fetch(_ access: String, project: String?, source: CredentialSource, fallback: Bool = false) {
        guard !stopped else { return }
        let host = fallback ? "cloudcode-pa.googleapis.com" : "daily-cloudcode-pa.googleapis.com"
        var request = URLRequest(url: URL(string: "https://\(host)/v1internal:retrieveUserQuotaSummary")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity/hub/2.24.0 (aidev_client; os_type=darwin; arch=arm64; cl=963137146)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: project.map { ["project": $0] } ?? [:])
        session.dataTask(with: request) { [weak self] data, response, _ in
            self?.queue.async { [weak self] in
                guard let self, !self.stopped else { return }
                if (response as? HTTPURLResponse)?.statusCode == 401 {
                    self.caches[source.accountID]?.expires = .distantPast
                }
                let reading = (response as? HTTPURLResponse)?.statusCode == 200 && (data?.count ?? .max) <= 1 << 20
                    ? data.flatMap { AgentAntigravityActivity.limits($0, observed: Date()) } : nil
                if var reading {
                    reading.accountID = source.accountID
                    reading.accountLabel = source.label
                    self.inFlightAccounts.remove(source.accountID)
                    self.saveCachedLimits(reading)
                    self.changed(reading)
                } else if !fallback {
                    self.fetch(access, project: project, source: source, fallback: true)
                } else {
                    self.inFlightAccounts.remove(source.accountID)
                }
            }
        }.resume()
    }
}
