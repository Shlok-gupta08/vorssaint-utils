// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation
import SwiftUI

/// A single configured account/profile for an AI coding provider (auto-discovered
/// from local tools / T3 Code or added manually by the user).
struct AgentAccount: Codable, Equatable, Identifiable {
    let id: String
    let provider: AgentProvider
    var label: String
    var sourcePath: String
    var t3InstanceID: String?
    var enabled: Bool
    var accentHex: String?
    var isAutoDiscovered: Bool

    init(id: String,
         provider: AgentProvider,
         label: String,
         sourcePath: String,
         t3InstanceID: String? = nil,
         enabled: Bool = true,
         accentHex: String? = nil,
         isAutoDiscovered: Bool = false) {
        self.id = id
        self.provider = provider
        self.label = label
        self.sourcePath = sourcePath
        self.t3InstanceID = t3InstanceID
        self.enabled = enabled
        self.accentHex = accentHex
        self.isAutoDiscovered = isAutoDiscovered
    }

    var expandedURL: URL {
        let expanded = (sourcePath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    var existsOnDisk: Bool {
        guard !sourcePath.isEmpty else { return t3InstanceID != nil }
        return FileManager.default.fileExists(atPath: expandedURL.path)
    }

    var customColor: Color? {
        guard let accentHex, !accentHex.isEmpty else { return nil }
        let cleaned = accentHex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Discovers and persists multi-account configurations across Claude, Codex,
/// Antigravity, and OpenCode, including multiple T3 Code provider instances.
enum AgentAccountRegistry {
    struct T3InstanceMetadata: Equatable {
        let instanceID: String
        let driver: String
        let displayName: String
        let enabled: Bool
    }

    static func t3ProviderInstances(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [T3InstanceMetadata] {
        let settingsURL = home.appending(path: ".t3/userdata/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let instances = json["providerInstances"] as? [String: [String: Any]] else {
            return []
        }
        return instances.map { key, value in
            let driver = (value["driver"] as? String ?? key).lowercased()
            let displayName = (value["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let enabled = value["enabled"] as? Bool ?? true
            return T3InstanceMetadata(
                instanceID: key,
                driver: driver,
                displayName: (displayName?.isEmpty == false ? displayName! : key),
                enabled: enabled
            )
        }.sorted { $0.instanceID < $1.instanceID }
    }

    /// Discovers accounts currently present on this Mac (default tool folders +
    /// T3 Code provider instances + T3 Antigravity token profiles).
    static func discovered(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentAccount] {
        var found: [AgentAccount] = []
        let fm = FileManager.default

        // 1. Default standalone roots per provider
        let claudePath = home.appending(path: ".claude")
        if fm.fileExists(atPath: claudePath.path) {
            found.append(AgentAccount(
                id: "default:claude",
                provider: .claude,
                label: "Claude (Default)",
                sourcePath: claudePath.path,
                t3InstanceID: "claude",
                enabled: true,
                isAutoDiscovered: true
            ))
        }

        let codexPath = home.appending(path: ".codex")
        if fm.fileExists(atPath: codexPath.path) {
            found.append(AgentAccount(
                id: "default:codex",
                provider: .codex,
                label: "Codex (Default)",
                sourcePath: codexPath.path,
                t3InstanceID: "codex",
                enabled: true,
                isAutoDiscovered: true
            ))
        }

        let openCodePath = home.appending(path: ".local/share/opencode")
        if fm.fileExists(atPath: openCodePath.path) {
            found.append(AgentAccount(
                id: "default:opencode",
                provider: .opencode,
                label: "OpenCode",
                sourcePath: openCodePath.path,
                enabled: true,
                isAutoDiscovered: true
            ))
        }

        // 2. T3 Antigravity profile directories (~/.t3/userdata/providers/antigravity/<sha256(instanceID)>)
        let t3Instances = t3ProviderInstances(home: home)
        let agT3Instances = t3Instances.filter { $0.driver == "antigravity" || $0.instanceID.hasPrefix("antigravity") }
        let instancesByHash: [String: T3InstanceMetadata] = Dictionary(
            uniqueKeysWithValues: agT3Instances.map { (sha256Hex($0.instanceID), $0) }
        )
        let t3AgRoot = home.appending(path: ".t3/userdata/providers/antigravity")
        let profileDirs = ((try? fm.contentsOfDirectory(at: t3AgRoot, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { dir in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for (index, dir) in profileDirs.enumerated() {
            let hash = dir.lastPathComponent
            let acpDir = dir.appending(path: "antigravity-acp")
            let oauthFile = acpDir.appending(path: "antigravity-oauth-token")
            let tokenFile = acpDir.appending(path: "acp_token.json")
            guard fm.fileExists(atPath: acpDir.path) || fm.fileExists(atPath: oauthFile.path) || fm.fileExists(atPath: tokenFile.path) else { continue }
            let matchedInstance = instancesByHash[hash]
                ?? (index < agT3Instances.count ? agT3Instances[index] : nil)
            let label = matchedInstance?.displayName ?? (profileDirs.count == 1 ? "Antigravity" : "Antigravity \(index + 1)")
            found.append(AgentAccount(
                id: "t3:antigravity:\(hash)",
                provider: .antigravity,
                label: label,
                sourcePath: acpDir.path,
                t3InstanceID: matchedInstance?.instanceID ?? (index == 0 ? "antigravity" : "antigravity_\(index + 1)"),
                enabled: matchedInstance?.enabled ?? true,
                isAutoDiscovered: true
            ))
        }

        // 3. Any additional T3 Code named provider instances (e.g., codex_2, claude_work)
        for instance in t3Instances {
            let provider: AgentProvider?
            if instance.driver.contains("antigravity") || instance.instanceID.hasPrefix("antigravity") {
                provider = .antigravity
            } else if instance.driver.contains("codex") || instance.instanceID.hasPrefix("codex") {
                provider = .codex
            } else if instance.driver.contains("claude") || instance.instanceID.hasPrefix("claude") {
                provider = .claude
            } else if instance.driver.contains("opencode") || instance.instanceID.hasPrefix("opencode") {
                provider = .opencode
            } else {
                provider = nil
            }
            guard let provider else { continue }
            if found.contains(where: { $0.t3InstanceID == instance.instanceID }) { continue }
            found.append(AgentAccount(
                id: "t3:\(provider.rawValue):\(instance.instanceID)",
                provider: provider,
                label: instance.displayName,
                sourcePath: "",
                t3InstanceID: instance.instanceID,
                enabled: instance.enabled,
                isAutoDiscovered: true
            ))
        }

        // 4. Standalone Antigravity (~/.gemini) if no T3 Antigravity or standalone token exists
        let geminiToken = home.appending(path: ".gemini/jetski-standalone-oauth-token")
        let geminiBrain = home.appending(path: ".gemini/antigravity/brain")
        if fm.fileExists(atPath: geminiToken.path) || fm.fileExists(atPath: geminiBrain.path) {
            found.append(AgentAccount(
                id: "default:antigravity-standalone",
                provider: .antigravity,
                label: profileDirs.isEmpty ? "Antigravity" : "Antigravity (Standalone)",
                sourcePath: home.appending(path: ".gemini").path,
                enabled: true,
                isAutoDiscovered: true
            ))
        }

        return found
    }

    static func savedRaw(in defaults: UserDefaults = .standard) -> [AgentAccount] {
        guard let raw = defaults.string(forKey: DefaultsKey.notchAgentsAccounts),
              !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AgentAccount].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ accounts: [AgentAccount], in defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(accounts),
              let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: DefaultsKey.notchAgentsAccounts)
    }

    /// Merges persisted user edits & custom accounts with auto-discovered accounts.
    static func accounts(in defaults: UserDefaults = .standard,
                         home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentAccount] {
        let saved = savedRaw(in: defaults)
        let auto = discovered(home: home)
        if saved.isEmpty { return auto }

        var result: [AgentAccount] = []
        var seen = Set<String>()
        for entry in saved {
            // Refresh disk existence & merge any missing t3InstanceID on auto accounts.
            var merged = entry
            if entry.isAutoDiscovered, let fresh = auto.first(where: { $0.id == entry.id }) {
                if merged.sourcePath.isEmpty { merged.sourcePath = fresh.sourcePath }
                if merged.t3InstanceID == nil {
                    merged.t3InstanceID = fresh.t3InstanceID
                } else if entry.id.hasPrefix("t3:antigravity:"),
                          let freshInstance = fresh.t3InstanceID,
                          merged.t3InstanceID != freshInstance {
                    // Repair previously swapped alphabetical T3 Antigravity hash -> instance mappings.
                    merged.t3InstanceID = freshInstance
                    merged.label = fresh.label
                }
            }
            if seen.insert(merged.id).inserted {
                result.append(merged)
            }
        }
        for fresh in auto where seen.insert(fresh.id).inserted {
            result.append(fresh)
        }
        return result
    }

    static func enabledAccounts(for provider: AgentProvider? = nil,
                                in defaults: UserDefaults = .standard,
                                home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentAccount] {
        accounts(in: defaults, home: home).filter { account in
            account.enabled && (provider == nil || account.provider == provider)
        }
    }

    static func resolveAccount(provider: AgentProvider,
                               t3InstanceID: String? = nil,
                               sourcePath: String? = nil,
                               in defaults: UserDefaults = .standard,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AgentAccount? {
        let list = accounts(in: defaults, home: home).filter { $0.provider == provider }
        if let t3InstanceID, !t3InstanceID.isEmpty,
           let matched = list.first(where: { $0.t3InstanceID == t3InstanceID }) {
            return matched
        }
        if let sourcePath, !sourcePath.isEmpty,
           let matched = list.first(where: { !$0.sourcePath.isEmpty && sourcePath.hasPrefix($0.expandedURL.path) }) {
            return matched
        }
        return list.first
    }

    /// Extra session log roots derived from user-added custom accounts.
    static func customLogRoots(in defaults: UserDefaults = .standard) -> [AgentLogRoot] {
        let customs = savedRaw(in: defaults).filter { !$0.isAutoDiscovered && $0.enabled && !$0.sourcePath.isEmpty }
        var roots: [AgentLogRoot] = []
        for account in customs {
            let base = account.expandedURL
            switch account.provider {
            case .claude:
                let projects = base.appending(path: "projects", directoryHint: .isDirectory)
                roots.append(AgentLogRoot(provider: .claude, url: AgentLogRoot.canonical(
                    FileManager.default.fileExists(atPath: projects.path) ? projects : base)))
            case .codex:
                let sessions = base.appending(path: "sessions", directoryHint: .isDirectory)
                roots.append(AgentLogRoot(provider: .codex, url: AgentLogRoot.canonical(
                    FileManager.default.fileExists(atPath: sessions.path) ? sessions : base)))
            case .opencode:
                roots.append(AgentLogRoot(provider: .opencode, url: AgentLogRoot.canonical(base)))
            case .antigravity:
                let brain = base.appending(path: "brain", directoryHint: .isDirectory)
                roots.append(AgentLogRoot(provider: .antigravity, url: AgentLogRoot.canonical(
                    FileManager.default.fileExists(atPath: brain.path) ? brain : base)))
            }
        }
        return roots
    }

    static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func provider(forT3Name raw: String) -> AgentProvider? {
        let lower = raw.lowercased()
        if lower == "antigravity" || lower.hasPrefix("antigravity_") || lower.hasPrefix("antigravity-") { return .antigravity }
        if lower == "codex" || lower.hasPrefix("codex_") || lower.hasPrefix("codex-") { return .codex }
        if lower == "claude" || lower.hasPrefix("claude_") || lower.hasPrefix("claude-") { return .claude }
        if lower == "opencode" || lower.hasPrefix("opencode_") || lower.hasPrefix("opencode-") { return .opencode }
        return nil
    }
}
