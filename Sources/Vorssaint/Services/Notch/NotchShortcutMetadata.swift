// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Matches only exact library names exposed by the native runner's accessibility
/// surface. Never guesses from the most recently edited shortcut or dialog text.
final class NotchShortcutMetadata {
    struct Value { let name: String; let icon: NSImage? }
    private var names: Set<String> = []
    var availableNames: [String] { names.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var lastNames = Date.distantPast
    private var cached: [String: NSImage] = [:]

    static func literal(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    func read(pid: Int32, now: Date) -> Value? {
        if now.timeIntervalSince(lastNames) >= 60 {
            lastNames = now
            let result = BoundedProcessRunner.run("/usr/bin/shortcuts", ["list"], timeout: 2, maxOutputBytes: 65536)
            if result.status == 0, !result.timedOut, let text = String(data: result.output, encoding: .utf8) {
                names = Set(text.split(separator: "\n").map(String.init))
            }
        }
        guard AXIsProcessTrusted(), !names.isEmpty else { return nil }
        var matches = Set<String>()
        var pids = [pid]
        for bundle in ["com.apple.shortcuts.events", "com.apple.shortcuts.ShortcutLiveActivityWidget"] {
            pids += NSRunningApplication.runningApplications(withBundleIdentifier: bundle).map(\.processIdentifier)
        }
        // Widget extensions and the dialog XPC service are not consistently
        // registered as NSRunningApplications. Resolve only Apple's exact paths.
        let processes = BoundedProcessRunner.run("/bin/ps", ["-axo", "pid=,comm="], timeout: 1, maxOutputBytes: 262144)
        if let text = String(data: processes.output, encoding: .utf8), processes.status == 0 {
            for line in text.split(separator: "\n") {
                let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard parts.count == 2, let processID = Int32(parts[0]) else { continue }
                let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if path == "/System/Applications/Shortcuts.app/Contents/PlugIns/ShortcutLiveActivityWidgetExtension.appex/Contents/MacOS/ShortcutLiveActivityWidgetExtension"
                    || path == "/System/Library/PrivateFrameworks/WorkflowKit.framework/XPCServices/ShortcutsViewService.xpc/Contents/MacOS/ShortcutsViewService" {
                    pids.append(processID)
                }
            }
        }
        let deadline = Date().addingTimeInterval(0.6)
        for candidate in Set(pids) {
            let root = AXUIElementCreateApplication(candidate)
            AXUIElementSetMessagingTimeout(root, 0.1)
            var pending: [(AXUIElement, Int)] = [(root, 0)], visited = 0
            while let (node, depth) = pending.popLast(), visited < 120, Date() < deadline {
                visited += 1
                var role: CFTypeRef?
                AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &role)
                if let role = role as? String, [kAXWindowRole, kAXStaticTextRole, kAXImageRole].contains(role) {
                    for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                        var value: CFTypeRef?
                        if AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success,
                           let title = value as? String, names.contains(title) { matches.insert(title) }
                    }
                }
                guard depth < 7 else { continue }
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &children) == .success,
                   let children = children as? [AXUIElement] {
                    pending += children.prefix(40).map { ($0, depth + 1) }
                }
            }
        }
        guard matches.count == 1, let name = matches.first else { return nil }
        return artwork(name)
    }

    func artwork(_ name: String) -> Value {
        guard names.contains(name) else { return Value(name: name, icon: nil) }
        if let icon = cached[name] { return Value(name: name, icon: icon) }
        // The official scripting interface returns this shortcut's own TIFF.
        let script = "tell application id \"com.apple.shortcuts\" to get icon of shortcut " + Self.literal(name)
        let result = BoundedProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 2, maxOutputBytes: 4 << 20)
        guard result.status == 0, !result.timedOut,
              let output = String(data: result.output, encoding: .utf8),
              let marker = output.range(of: "data TIFF"), let end = output[marker.upperBound...].firstIndex(of: "»")
        else { return Value(name: name, icon: nil) }
        let hex = output[marker.upperBound..<end].filter { !$0.isWhitespace }
        guard hex.count.isMultiple(of: 2) else { return Value(name: name, icon: nil) }
        var data = Data(), index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return Value(name: name, icon: nil) }
            data.append(byte); index = next
        }
        let icon = NSImage(data: data)
        if let icon { if cached.count >= 32 { cached.removeAll() }; cached[name] = icon }
        return Value(name: name, icon: icon)
    }
}
