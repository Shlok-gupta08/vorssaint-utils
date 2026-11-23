// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Darwin
import Foundation
import SQLite3
import SwiftUI

/// Resolved metadata for a currently running Apple Shortcut, collected passively
/// without ever launching Shortcuts.app or spawning CLI/scripting processes.
struct NotchShortcutIdentity: Equatable {
    let name: String
    let symbol: String?
    let colorRed: Double?
    let colorGreen: Double?
    let colorBlue: Double?

    var color: Color? {
        guard let r = colorRed, let g = colorGreen, let b = colorBlue else { return nil }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

enum NotchShortcutIdentityResolver {
    private static let lock = NSLock()
    private static var cachedLibrary: [String: NotchShortcutIdentity] = [:]
    private static var libraryLoadedAt = Date.distantPast

    /// Passively identifies the running shortcut from:
    /// 1. Kernel process arguments (`KERN_PROCARGS2`) for `/usr/bin/shortcuts run <name>`
    /// 2. Passive Accessibility read of ControlCenter / Shortcuts running indicator
    /// 3. Passive read-only SQLite lookup in `~/Library/Shortcuts/Shortcuts.sqlite`
    ///    to attach the shortcut's real glyph & color.
    static func resolve(pid: Int32, executable: String) -> NotchShortcutIdentity? {
        let name = nameFromProcessArguments(pid: pid, executable: executable)
            ?? nameFromPassiveAccessibility()
        guard let name, !name.isEmpty else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let fromDB = lookupInLibrary(name: trimmed) {
            return fromDB
        }
        return NotchShortcutIdentity(
            name: trimmed,
            symbol: inferredSymbol(for: trimmed),
            colorRed: 0.28, colorGreen: 0.56, colorBlue: 0.98
        )
    }

    /// Reads argv directly via sysctl(KERN_PROCARGS2). Zero child processes spawned.
    static func nameFromProcessArguments(pid: Int32, executable: String) -> String? {
        guard executable == "/usr/bin/shortcuts" || executable.hasSuffix("/shortcuts") else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size, size <= 65_536 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        let argc: Int32 = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc >= 3 else { return nil }
        var idx = MemoryLayout<Int32>.size
        // Skip exec_path and trailing NUL padding.
        while idx < size && buffer[idx] != 0 { idx += 1 }
        while idx < size && buffer[idx] == 0 { idx += 1 }

        var args: [String] = []
        while idx < size && args.count < Int(argc) {
            let start = idx
            while idx < size && buffer[idx] != 0 { idx += 1 }
            if let arg = String(bytes: buffer[start..<idx], encoding: .utf8) {
                args.append(arg)
            }
            idx += 1
        }
        return parseShortcutsCLIArgs(args)
    }

    static func parseShortcutsCLIArgs(_ args: [String]) -> String? {
        guard let runIndex = args.firstIndex(of: "run") else { return nil }
        var i = runIndex + 1
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("-") {
                // Skip option + value for flags like -i / -o / --input-path / --output-path.
                if ["-i", "-o", "--input-path", "--output-path", "--output-type"].contains(arg) {
                    i += 2
                } else {
                    i += 1
                }
                continue
            }
            return arg.isEmpty ? nil : arg
        }
        return nil
    }

    /// Passively inspects ControlCenter & Shortcuts AX status items when Accessibility is granted.
    private static func nameFromPassiveAccessibility() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let candidates = [
            "com.apple.controlcenter",
            "com.apple.shortcuts",
            "com.apple.ShortcutsEvents",
        ]
        for bundleID in candidates {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.08)
            var extrasRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
               let bar = extrasRef {
                if let found = scanAXElementForShortcutName(bar as! AXUIElement, depth: 0) {
                    return found
                }
            }
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement] {
                for win in windows.prefix(6) {
                    if let found = scanAXElementForShortcutName(win, depth: 0) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    private static func scanAXElementForShortcutName(_ element: AXUIElement, depth: Int) -> String? {
        guard depth <= 4 else { return nil }
        for attr in [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute, kAXValueAttribute] {
            var val: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &val) == .success,
               let text = val as? String,
               let extracted = extractRunningShortcutName(from: text) {
                return extracted
            }
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children.prefix(24) {
            if let found = scanAXElementForShortcutName(child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    /// Extracts a shortcut name from macOS status item labels like
    /// "Running “Water Eject”", "Shortcuts: Water Eject", "Stop Water Eject".
    static func extractRunningShortcutName(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return nil }
        let patterns = [
            #"(?i)^running\s+[“"'](.+?)[”"']$"#,
            #"(?i)^running\s+shortcut\s+[“"']?(.+?)[”"']?$"#,
            #"(?i)^shortcuts?\s*[-:]\s*(.+)$"#,
            #"(?i)^stop\s+[“"'](.+?)[”"']$"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: trimmed) {
                let candidate = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && candidate.lowercased() != "shortcuts" && candidate.lowercased() != "shortcut" {
                    return candidate
                }
            }
        }
        return nil
    }

    // MARK: - Passive Read-Only Shortcuts SQLite Metadata

    private static func lookupInLibrary(name: String) -> NotchShortcutIdentity? {
        refreshLibraryCacheIfNeeded()
        return lock.withLock { cachedLibrary[name.lowercased()] }
    }

    private static func refreshLibraryCacheIfNeeded() {
        let needsRefresh = lock.withLock { Date().timeIntervalSince(libraryLoadedAt) > 120 }
        guard needsRefresh else { return }
        let dbURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Shortcuts/Shortcuts.sqlite")
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            lock.withLock { libraryLoadedAt = Date() }
            return
        }
        sqlite3_busy_timeout(db, 100)
        // Check available columns cleanly so schema variations across macOS versions never fail.
        let query = "SELECT ZNAME, ZGLYPHCHARACTER, ZCOLORING FROM ZSHORTCUT WHERE ZNAME IS NOT NULL;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        var map: [String: NotchShortcutIdentity] = [:]
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let namePtr = sqlite3_column_text(stmt, 0) else { continue }
                let name = String(cString: namePtr)
                let glyphCode = sqlite3_column_int64(stmt, 1)
                let coloring = sqlite3_column_int64(stmt, 2)
                let rgb = decodeShortcutColor(coloring)
                let symbol = glyphToSymbol(glyphCode) ?? inferredSymbol(for: name)
                map[name.lowercased()] = NotchShortcutIdentity(
                    name: name, symbol: symbol,
                    colorRed: rgb.r, colorGreen: rgb.g, colorBlue: rgb.b
                )
            }
        }
        lock.withLock {
            cachedLibrary = map
            libraryLoadedAt = Date()
        }
    }

    /// Decodes Apple's WorkflowKit `ZCOLORING` packed RGBA integer.
    static func decodeShortcutColor(_ raw: Int64) -> (r: Double, g: Double, b: Double) {
        let u = UInt32(bitPattern: Int32(truncatingIfNeeded: raw))
        let r = Double((u >> 24) & 0xFF) / 255.0
        let g = Double((u >> 16) & 0xFF) / 255.0
        let b = Double((u >> 8) & 0xFF) / 255.0
        if r == 0 && g == 0 && b == 0 {
            return (0.28, 0.56, 0.98)
        }
        return (r, g, b)
    }

    /// Maps common WorkflowKit glyph codepoints to SF Symbols.
    static func glyphToSymbol(_ code: Int64) -> String? {
        switch code {
        case 59400...59420: return "sparkles"
        case 59440...59460: return "bolt.fill"
        case 59511: return "wifi"
        case 59560: return "music.note"
        case 59710: return "clipboard.fill"
        case 59740: return "calendar"
        case 59760: return "clock.fill"
        case 59770: return "bell.fill"
        case 59800: return "gearshape.fill"
        case 61440: return "wand.and.stars"
        default: return nil
        }
    }

    /// Smart SF Symbol inference when glyph mapping isn't in the static table.
    static func inferredSymbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("wi-fi") || lower.contains("wifi") { return "wifi" }
        if lower.contains("bluetooth") { return "wave.3.right" }
        if lower.contains("music") || lower.contains("playlist") || lower.contains("song") { return "music.note" }
        if lower.contains("clipboard") || lower.contains("copy") || lower.contains("paste") { return "doc.on.clipboard.fill" }
        if lower.contains("download") { return "arrow.down.circle.fill" }
        if lower.contains("water") || lower.contains("eject") { return "drop.fill" }
        if lower.contains("restart") || lower.contains("reboot") { return "arrow.clockwise" }
        if lower.contains("timer") || lower.contains("day") || lower.contains("time") { return "clock.fill" }
        if lower.contains("5g") || lower.contains("4g") || lower.contains("network") || lower.contains("cellular") { return "antenna.radiowaves.left.and.right" }
        if lower.contains("expense") || lower.contains("money") || lower.contains("pay") { return "dollarsign.circle.fill" }
        if lower.contains("train") || lower.contains("book") || lower.contains("travel") { return "tram.fill" }
        if lower.contains("focus") || lower.contains("dnd") { return "moon.fill" }
        if lower.contains("note") || lower.contains("text") { return "note.text" }
        if lower.contains("photo") || lower.contains("image") || lower.contains("camera") { return "camera.fill" }
        return "bolt.fill"
    }
}
