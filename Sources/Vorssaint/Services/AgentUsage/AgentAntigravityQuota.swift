// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

private final class AgentQuotaRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Quotas remain available when the native ACP adapter has no local hub.
/// Credentials are read-only and tokens stay in memory, sent only to Google.
final class AgentAntigravityQuota {
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
        let root = home.appending(path: ".t3/userdata/providers/antigravity")
        let profiles = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let files = profiles.map { $0.appending(path: "antigravity-acp/acp_token.json") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        // Never silently combine different signed-in accounts.
        if files.count == 1 { return files }
        if files.count > 1 { return [] }
        return [home.appending(path: ".gemini/jetski-standalone-oauth-token")]
    }

    private let home: URL
    private let queue: DispatchQueue
    private let changed: (AgentLimits) -> Void
    private let session: URLSession
    private var stopped = false
    private var inFlight = false
    private var lastPoll = Date.distantPast
    private var credential: Credential?
    private var access: String?
    private var expires = Date.distantPast

    init(queue: DispatchQueue, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         configuration: URLSessionConfiguration? = nil, changed: @escaping (AgentLimits) -> Void) {
        self.home = home; self.queue = queue; self.changed = changed
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: AgentQuotaRedirectPolicy(), delegateQueue: nil)
    }

    func stop() { stopped = true; session.invalidateAndCancel(); credential = nil; access = nil }
    deinit { session.invalidateAndCancel() }

    func poll(now: Date) {
        guard !stopped, !inFlight, now.timeIntervalSince(lastPoll) >= 60 else { return }
        lastPoll = now
        guard let path = Self.credentialURLs(home: home).first,
              let size = (try? path.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 65536,
              let data = try? Data(contentsOf: path), let next = Credential.decode(data) else { return }
        if next != credential { credential = next; access = nil; expires = .distantPast }
        inFlight = true
        if let access, expires > now.addingTimeInterval(60) { fetch(access, project: next.project); return }
        if let access = next.accessToken, let expiry = next.expiry, expiry > now.addingTimeInterval(60) {
            self.access = access; expires = expiry; fetch(access, project: next.project); return
        }
        guard let id = next.clientID, let secret = next.clientSecret, let refresh = next.refreshToken else {
            inFlight = false; return
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [URLQueryItem(name: "client_id", value: id), URLQueryItem(name: "client_secret", value: secret),
            URLQueryItem(name: "refresh_token", value: refresh), URLQueryItem(name: "grant_type", value: "refresh_token")]
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        session.dataTask(with: request) { [weak self] data, response, _ in
            self?.queue.async { [weak self] in
                guard let self, !self.stopped else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count <= 65536,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let access = json["access_token"] as? String, !access.isEmpty,
                      let duration = json["expires_in"] as? Double, duration > 0 else { self.inFlight = false; return }
                self.access = access; self.expires = Date().addingTimeInterval(duration)
                self.fetch(access, project: next.project)
            }
        }.resume()
    }

    private func fetch(_ access: String, project: String?, fallback: Bool = false) {
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
                if (response as? HTTPURLResponse)?.statusCode == 401 { self.expires = .distantPast }
                let reading = (response as? HTTPURLResponse)?.statusCode == 200 && (data?.count ?? .max) <= 1 << 20
                    ? data.flatMap { AgentAntigravityActivity.limits($0, observed: Date()) } : nil
                if let reading { self.inFlight = false; self.changed(reading) }
                else if !fallback { self.fetch(access, project: project, fallback: true) }
                else { self.inFlight = false }
            }
        }.resume()
    }
}
