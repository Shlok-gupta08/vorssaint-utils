// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI

struct NotchFocusState: Equatable {
    let isActive: Bool
    let identifier: String
    let name: String
    let symbol: String
    let tintName: String

    static let off = NotchFocusState(
        isActive: false,
        identifier: "com.apple.donotdisturb.mode.default",
        name: "Focus",
        symbol: "moon.fill",
        tintName: "indigo"
    )

    var tintColor: Color {
        switch tintName.lowercased() {
        case "purple", "systempurplecolor": return .purple
        case "indigo", "systemindigocolor": return .indigo
        case "blue", "systembluecolor": return .blue
        case "teal", "systemtealcolor": return .teal
        case "mint", "systemmintcolor": return .mint
        case "green", "systemgreencolor": return .green
        case "yellow", "systemyellowcolor": return .yellow
        case "orange", "systemorangecolor": return .orange
        case "red", "systemredcolor": return .red
        case "pink", "systempinkcolor": return .pink
        default: return .indigo
        }
    }
}

enum NotchFocusSupport {
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && (defaults.object(forKey: DefaultsKey.notchFocusEnabled) as? Bool ?? true)
    }

    static func hidesNativeBanner(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults)
            && (defaults.object(forKey: DefaultsKey.notchFocusHideNative) as? Bool ?? true)
    }

    static let logPredicate = "(subsystem == 'com.apple.donotdisturb' OR subsystem == 'com.apple.focus') "
        + "AND (eventMessage CONTAINS[c] 'state' OR eventMessage CONTAINS[c] 'mode' OR eventMessage CONTAINS[c] 'assertion')"

    /// Built-in macOS Focus profiles by mode identifier or localized title.
    static func metadata(for identifierOrName: String) -> (name: String, symbol: String, tint: String) {
        let lower = identifierOrName.lowercased()
        if lower.contains("sleep") || lower.contains("bedtime") {
            return ("Sleep", "bed.double.fill", "teal")
        }
        if lower.contains("work") {
            return ("Work", "person.crop.square.fill", "teal")
        }
        if lower.contains("personal") {
            return ("Personal", "person.fill", "purple")
        }
        if lower.contains("driving") || lower.contains("car") {
            return ("Driving", "car.fill", "indigo")
        }
        if lower.contains("fitness") || lower.contains("workout") {
            return ("Fitness", "figure.run", "green")
        }
        if lower.contains("gaming") || lower.contains("game") {
            return ("Gaming", "gamecontroller.fill", "indigo")
        }
        if lower.contains("mindfulness") {
            return ("Mindfulness", "figure.mind.and.body", "mint")
        }
        if lower.contains("reading") {
            return ("Reading", "book.fill", "orange")
        }
        if lower.contains("reduce-interruptions") || lower.contains("reduce interruptions") {
            return ("Reduce Interruptions", "sparkles", "indigo")
        }
        if lower.contains("donotdisturb") || lower.contains("do not disturb") || lower.contains("default") || lower.isEmpty {
            return ("Do Not Disturb", "moon.fill", "indigo")
        }
        let cleaned = identifierOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Focus" : cleaned, "moon.fill", "indigo")
    }

    /// Parses a native macOS NotificationCenter Focus banner's AX text strings.
    /// Returns nil for any non-Focus notification.
    static func parseBannerStrings(_ strings: [String], knownModes: [String: (name: String, symbol: String, tint: String)] = [:]) -> NotchFocusState? {
        let cleaned = strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        let joined = cleaned.joined(separator: " ")
        let lower = joined.lowercased()

        // Must look like a Focus / Do Not Disturb status banner (never a prose sentence like "focus on work").
        // Split comma-separated AXAttributedDescription segments too (e.g. "Focus, Do Not Disturb, On").
        let lowerFields = cleaned
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let isOn = lowerFields.contains(where: { field in
            field == "on" || field == "turned on" || field == "focus on"
                || field.hasSuffix(" on") || field.hasSuffix("—on") || field.hasSuffix(": on")
                || field.contains("turned on") || field.contains("notifications silenced")
        })
        let isOff = lowerFields.contains(where: { field in
            field == "off" || field == "turned off" || field == "focus off"
                || field.hasSuffix(" off") || field.hasSuffix("—off") || field.hasSuffix(": off")
                || field.contains("turned off")
        })
        guard isOn || isOff else { return nil }

        let standardNames = ["do not disturb", "work", "personal", "sleep", "driving", "fitness", "gaming", "mindfulness", "reading", "reduce interruptions", "focus"]
        let matchedKnown = knownModes.values.first { lower.contains($0.name.lowercased()) }
        let matchedStandard = standardNames.first { lower.contains($0) }
        guard matchedKnown != nil || matchedStandard != nil else { return nil }

        // Reject ordinary app notifications that merely mention the word "focus" or "work" in a message body.
        guard cleaned.count <= 6, joined.count <= 120 else { return nil }

        let active = isOn && !isOff
        if let matchedKnown {
            return NotchFocusState(isActive: active, identifier: matchedKnown.name, name: matchedKnown.name,
                                   symbol: matchedKnown.symbol, tintName: matchedKnown.tint)
        }
        let meta = metadata(for: matchedStandard ?? "Do Not Disturb")
        return NotchFocusState(isActive: active, identifier: meta.name, name: meta.name,
                               symbol: meta.symbol, tintName: meta.tint)
    }

    /// Parses DoNotDisturb DB `Assertions.json` and `ModeConfigurations.json` when accessible.
    static func parseDatabase(assertionsData: Data?, modesData: Data?) -> (active: NotchFocusState?, modes: [String: (name: String, symbol: String, tint: String)]) {
        var modes: [String: (name: String, symbol: String, tint: String)] = [:]
        if let modesData,
           let root = (try? JSONSerialization.jsonObject(with: modesData)) as? [String: Any],
           let dataArr = root["data"] as? [[String: Any]],
           let first = dataArr.first,
           let configs = first["modeConfigurations"] as? [String: [String: Any]] {
            for (key, config) in configs {
                guard let mode = config["mode"] as? [String: Any] else { continue }
                let identifier = mode["modeIdentifier"] as? String ?? key
                let name = mode["name"] as? String ?? metadata(for: identifier).name
                let symbol = mode["symbolImageName"] as? String ?? metadata(for: identifier).symbol
                let tint = mode["tintColorName"] as? String ?? metadata(for: identifier).tint
                modes[identifier] = (name, symbol, tint)
            }
        }

        guard let assertionsData,
              let root = (try? JSONSerialization.jsonObject(with: assertionsData)) as? [String: Any],
              let dataArr = root["data"] as? [[String: Any]],
              let first = dataArr.first,
              let records = first["storeAssertionRecords"] as? [[String: Any]] else {
            return (nil, modes)
        }

        for record in records {
            if let details = record["assertionDetails"] as? [String: Any],
               let modeID = details["assertionDetailsModeIdentifier"] as? String, !modeID.isEmpty {
                let meta = modes[modeID] ?? metadata(for: modeID)
                return (NotchFocusState(isActive: true, identifier: modeID, name: meta.name, symbol: meta.symbol, tintName: meta.tint), modes)
            }
        }
        return (nil, modes)
    }

    /// Parses `donotdisturbd` / `FocusDaemon` unified log lines for state transitions.
    static func parseLogEvent(_ data: Data) -> (isActive: Bool, modeIdentifier: String?)? {
        guard data.count <= 32 << 10,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let message = json["eventMessage"] as? String else { return nil }
        let lower = message.lowercased()
        // Match explicit active state updates emitted by donotdisturbd.
        guard lower.contains("active=") || lower.contains("isactive") || lower.contains("stateupdate") || lower.contains("didchangeactive") else {
            return nil
        }
        let isActive: Bool
        if lower.contains("active=yes") || lower.contains("active = 1") || lower.contains("isactive: 1") || lower.contains("isactive=yes") || lower.contains("active: yes") {
            isActive = true
        } else if lower.contains("active=no") || lower.contains("active = 0") || lower.contains("isactive: 0") || lower.contains("isactive=no") || lower.contains("active: no") {
            isActive = false
        } else {
            return nil
        }
        var modeID: String?
        if let range = message.range(of: #"modeIdentifier[=:\s]+"?([A-Za-z0-9._-]+)"?"#, options: .regularExpression) {
            let slice = String(message[range])
            modeID = slice.split(whereSeparator: { $0 == "=" || $0 == ":" || $0 == " " || $0 == "\"" }).last.map(String.init)
        }
        return (isActive, modeID)
    }
}
