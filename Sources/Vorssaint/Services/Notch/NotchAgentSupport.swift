// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The cards the AI page can show, in the order a person arranges them. Raw
/// values are stored in the saved order, so cases are never renamed.
enum NotchAgentCard: String, CaseIterable, Identifiable {
    case limits, spend, live, trend, models, projects, activity, resets

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .limits: return "gauge.with.dots.needle.33percent"
        case .spend: return "dollarsign.circle"
        case .live: return "waveform.path.ecg"
        case .trend: return "chart.bar.xaxis"
        case .models: return "cpu"
        case .projects: return "folder"
        case .activity: return "square.grid.3x3.fill"
        case .resets: return "arrow.counterclockwise.circle"
        }
    }

    /// Charts need the island's width; everything else pairs up.
    var fullWidth: Bool { self == .trend || self == .activity }
}

/// What the closed island shows beside the camera while an agent works.
enum NotchAgentReadout: String, CaseIterable, Identifiable {
    case elapsed, tokens, cost, limit
    var id: String { rawValue }

    /// Tokens and cost change only with a new snapshot. Limits still need
    /// the clock: an allowance can renew, or show elapsed time while unknown.
    var advancesWithClock: Bool { self == .elapsed || self == .limit }
}

enum NotchAgentLimitDisplay: String, CaseIterable, Identifiable {
    case remaining, used
    var id: String { rawValue }
}

/// Which allowance the closed island shows.
enum NotchAgentLimitFocus: String, CaseIterable, Identifiable {
    case mostUsed, session, weekly
    var id: String { rawValue }
}

/// Customizable Notch layout configuration for the AI Agents page and pill.
struct NotchAgentLayoutConfig: Codable, Equatable {
    enum ColumnMode: String, CaseIterable, Identifiable, Codable {
        case auto, twoColumn, singleColumn
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: return "Auto"
            case .twoColumn: return "2 Columns"
            case .singleColumn: return "1 Column"
            }
        }
    }

    enum Density: String, CaseIterable, Identifiable, Codable {
        case standard, compact
        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: return "Standard"
            case .compact: return "Compact"
            }
        }
    }

    enum AccountCardMode: String, CaseIterable, Identifiable, Codable {
        case separateAccounts, combinedByProvider
        var id: String { rawValue }
        var title: String {
            switch self {
            case .separateAccounts: return "Separate Card per Account"
            case .combinedByProvider: return "Combined by Provider"
            }
        }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case balanced, limitsFocus, liveOps, compact
        var id: String { rawValue }
        var title: String {
            switch self {
            case .balanced: return "Balanced"
            case .limitsFocus: return "Limits Focus"
            case .liveOps: return "Live Ops"
            case .compact: return "Compact"
            }
        }
    }

    var columnMode: ColumnMode = .auto
    var density: Density = .standard
    var accountCardMode: AccountCardMode = .separateAccounts
    /// Card raw values explicitly forced to full width (or half width when in halfWidthCards).
    var fullWidthCards: Set<String> = []
    var halfWidthCards: Set<String> = []
    var showAccountLabelInPill: Bool = true

    static let `default` = NotchAgentLayoutConfig()

    static func current(in defaults: UserDefaults = .standard) -> NotchAgentLayoutConfig {
        guard let raw = defaults.string(forKey: DefaultsKey.notchAgentsLayoutConfig),
              !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(NotchAgentLayoutConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              let raw = String(data: data, encoding: .utf8) else { return }
        defaults.set(raw, forKey: DefaultsKey.notchAgentsLayoutConfig)
    }

    func isFullWidth(card: NotchAgentCard) -> Bool {
        if fullWidthCards.contains(card.rawValue) { return true }
        if halfWidthCards.contains(card.rawValue) { return false }
        return card.fullWidth
    }

    mutating func setFullWidth(_ full: Bool, for card: NotchAgentCard) {
        if full {
            fullWidthCards.insert(card.rawValue)
            halfWidthCards.remove(card.rawValue)
        } else {
            halfWidthCards.insert(card.rawValue)
            fullWidthCards.remove(card.rawValue)
        }
    }

    func cardHeight(fullWidth: Bool) -> CGFloat {
        switch (density, fullWidth) {
        case (.standard, true): return NotchAgentSupport.chartHeight
        case (.standard, false): return NotchAgentSupport.cardHeight
        case (.compact, true): return 96
        case (.compact, false): return 78
        }
    }

    static func applyPreset(_ preset: Preset, to defaults: UserDefaults = .standard) {
        var config = current(in: defaults)
        switch preset {
        case .balanced:
            config = .default
            defaults.set(NotchAgentCard.allCases.map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.notchAgentsCardOrder)
            defaults.set("", forKey: DefaultsKey.notchAgentsHiddenCards)
        case .limitsFocus:
            config.columnMode = .twoColumn
            config.density = .standard
            config.accountCardMode = .separateAccounts
            config.fullWidthCards = []
            config.halfWidthCards = []
            defaults.set([NotchAgentCard.limits, .live, .spend, .trend, .resets, .models, .projects, .activity].map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.notchAgentsCardOrder)
            defaults.set([NotchAgentCard.projects, .activity].map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.notchAgentsHiddenCards)
        case .liveOps:
            config.columnMode = .twoColumn
            config.density = .standard
            config.accountCardMode = .separateAccounts
            config.fullWidthCards = [NotchAgentCard.live.rawValue]
            config.halfWidthCards = []
            defaults.set([NotchAgentCard.live, .limits, .spend, .models, .trend, .projects, .resets, .activity].map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.notchAgentsCardOrder)
            defaults.set([NotchAgentCard.activity].map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.notchAgentsHiddenCards)
        case .compact:
            config.columnMode = .twoColumn
            config.density = .compact
            config.accountCardMode = .combinedByProvider
            config.fullWidthCards = []
            config.halfWidthCards = [NotchAgentCard.trend.rawValue]
            defaults.set([NotchAgentCard.limits, .live, .spend, .trend].map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.notchAgentsCardOrder)
            defaults.set([NotchAgentCard.models, .projects, .activity, .resets].map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.notchAgentsHiddenCards)
        }
        config.save(to: defaults)
    }
}

struct NotchAgentTile: Identifiable, Equatable {
    let card: NotchAgentCard
    /// The provider a limits/resets card belongs to.
    let provider: AgentProvider?
    /// Optional specific account when separate-account mode is enabled.
    var accountID: String? = nil
    var accountLabel: String? = nil
    var accountAccentHex: String? = nil
    var customFullWidth: Bool? = nil

    var effectiveFullWidth: Bool { customFullWidth ?? card.fullWidth }

    var id: String {
        var base = card.rawValue
        if let provider { base += "." + provider.rawValue }
        if let accountID { base += "@" + accountID }
        return base
    }
}

enum NotchAgentSupport {
    static let defaultFinishMinimum: TimeInterval = 60
    static let finishMinimums: [TimeInterval] = [0, 30, 60, 120, 300]
    static let defaultLimitThreshold = 80.0
    static let limitThresholds = [50.0, 75.0, 80.0, 90.0, 95.0]
    static let budgets = [0.0, 5, 10, 25, 50, 100, 250]
    /// A turn silent for this long is not shown as working.
    static let idleTurn: TimeInterval = 10 * 60

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchAgents.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchAgentsEnabled)
            && NotchSupport.modules(in: defaults).contains(.agents)
    }

    static func providers(in defaults: UserDefaults = .standard) -> [AgentProvider] {
        AgentProvider.allCases.filter {
            defaults.object(forKey: key(for: $0)) as? Bool ?? true
        }
    }

    static func key(for provider: AgentProvider) -> String {
        switch provider {
        case .claude: return DefaultsKey.notchAgentsClaude
        case .codex: return DefaultsKey.notchAgentsCodex
        case .opencode: return DefaultsKey.notchAgentsOpenCode
        case .antigravity: return DefaultsKey.notchAgentsAntigravity
        }
    }

    /// Every card in the saved order; cards added later join at the end.
    static func orderedCards(in defaults: UserDefaults = .standard) -> [NotchAgentCard] {
        let stored = (defaults.string(forKey: DefaultsKey.notchAgentsCardOrder) ?? "")
            .split(separator: ",").compactMap { NotchAgentCard(rawValue: String($0)) }
        var seen = Set<NotchAgentCard>()
        return (stored + NotchAgentCard.allCases).filter { seen.insert($0).inserted }
    }

    static func hiddenCards(in defaults: UserDefaults = .standard) -> Set<NotchAgentCard> {
        Set((defaults.string(forKey: DefaultsKey.notchAgentsHiddenCards) ?? "")
            .split(separator: ",").compactMap { NotchAgentCard(rawValue: String($0)) })
    }

    static func cards(in defaults: UserDefaults = .standard) -> [NotchAgentCard] {
        let hidden = hiddenCards(in: defaults)
        return orderedCards(in: defaults).filter { !hidden.contains($0) }
    }

    static func period(in defaults: UserDefaults = .standard) -> AgentPeriod {
        AgentPeriod(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsPeriod) ?? "") ?? .today
    }

    static func limitDisplay(in defaults: UserDefaults = .standard) -> NotchAgentLimitDisplay {
        NotchAgentLimitDisplay(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsLimitDisplay) ?? "") ?? .remaining
    }

    static func limitFocus(in defaults: UserDefaults = .standard) -> NotchAgentLimitFocus {
        NotchAgentLimitFocus(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsLimitFocus) ?? "") ?? .mostUsed
    }

    /// The allowance the closed island shows: the window the person chose,
    /// or the one closest to running out while the account reports no such
    /// window. A model's own allowance is never the chosen one.
    static func focusedLimit(_ limits: AgentLimits?, focus: NotchAgentLimitFocus, now: Date) -> AgentLimitWindow? {
        chosenLimit(limits, focus: focus, now: now) ?? AgentLimitSupport.binding(limits, now: now)
    }

    /// The plan-wide window of the chosen kind; nil for the most used one or
    /// while the account reports no such window.
    private static func chosenLimit(_ limits: AgentLimits?, focus: NotchAgentLimitFocus, now: Date) -> AgentLimitWindow? {
        let kind: AgentLimitWindow.Kind
        switch focus {
        case .mostUsed: return nil
        case .session: kind = .session
        case .weekly: kind = .weekly
        }
        if let unscoped = limits?.windows.first(where: { $0.kind == kind && $0.scope == nil }) {
            return AgentLimitSupport.current(unscoped, at: now)
        }
        return limits?.windows.filter { $0.kind == kind }.max { $0.usedPercent < $1.usedPercent }.map { AgentLimitSupport.current($0, at: now) }
    }

    /// The resting island's allowance across every account: the most spent
    /// of the chosen windows, or of each account's most used window while no
    /// account reports the chosen one.
    static func restingLimit(_ snapshot: AgentUsageSnapshot, focus: NotchAgentLimitFocus,
                             now: Date) -> (provider: AgentProvider, window: AgentLimitWindow)? {
        func mostSpent(_ pick: (AgentLimits) -> AgentLimitWindow?) -> (provider: AgentProvider, window: AgentLimitWindow)? {
            snapshot.limits.compactMap { provider, limits in pick(limits).map { (provider: provider, window: $0) } }.max {
                $0.window.usedPercent != $1.window.usedPercent ? $0.window.usedPercent < $1.window.usedPercent
                    : $0.provider.rawValue > $1.provider.rawValue
            }
        }
        return mostSpent { chosenLimit($0, focus: focus, now: now) }
            ?? mostSpent { AgentLimitSupport.binding($0, now: now) }
    }

    static func showsLiveActivity(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && (defaults.object(forKey: DefaultsKey.notchAgentsLiveActivity) as? Bool ?? true)
    }

    static func readout(in defaults: UserDefaults = .standard) -> NotchAgentReadout {
        NotchAgentReadout(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsReadout) ?? "") ?? .elapsed
    }

    /// The shortest turn worth a notice when it ends; nil while those are off.
    static func finishMinimum(in defaults: UserDefaults = .standard) -> TimeInterval? {
        guard defaults.object(forKey: DefaultsKey.notchAgentsFinishAlert) as? Bool ?? true else { return nil }
        let value = defaults.object(forKey: DefaultsKey.notchAgentsFinishMinimum) as? Double ?? defaultFinishMinimum
        return value.isFinite ? min(3600, max(0, value)) : defaultFinishMinimum
    }

    /// Percent used that earns a warning; nil while warnings are off.
    static func limitThreshold(in defaults: UserDefaults = .standard) -> Double? {
        guard defaults.object(forKey: DefaultsKey.notchAgentsLimitAlert) as? Bool ?? true else { return nil }
        let value = defaults.object(forKey: DefaultsKey.notchAgentsLimitThreshold) as? Double ?? defaultLimitThreshold
        return value.isFinite ? min(100, max(1, value)) : defaultLimitThreshold
    }

    static func dailyBudget(in defaults: UserDefaults = .standard) -> Double? {
        let value = defaults.double(forKey: DefaultsKey.notchAgentsDailyBudget)
        return value.isFinite && value > 0 ? value : nil
    }

    /// Whether the public price list may be downloaded once a day.
    static func updatesPrices(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchAgentsPriceUpdates) as? Bool ?? true
    }

    // MARK: Strip

    /// Multiple agents keep their full-size marks; available menu-bar room
    /// still bounds the wings on each display.
    static let stripWingRange: ClosedRange<CGFloat> = 44...220
    static let stripMarkSpacing: CGFloat = 10
    static let stripMarkEdgePadding: CGFloat = 5
    static func stripMarkSize(height: CGFloat) -> CGFloat {
        min(18, max(8, height - NotchLayout.compactEdgeGap * 2 - 4))
    }
    static func stripMarksWidth(working: Int, height: CGFloat) -> CGFloat {
        let count = CGFloat(max(1, working))
        return count * (stripMarkSize(height: height) * 1.45 + 1) + (count - 1) * stripMarkSpacing
    }
    static func stripMarksWing(working: Int, geometry: NotchGeometry) -> CGFloat {
        stripMarksWidth(working: working, height: geometry.compactActivityContentHeight)
            + stripMarkOuterInset(geometry: geometry) + stripCameraGap
    }
    static func stripMarkOuterInset(geometry: NotchGeometry) -> CGFloat {
        let side = stripMarkSize(height: geometry.compactActivityContentHeight)
        let inset = geometry.compactActivityEdgeInset(boxHeight: side * 1.45 + 1, radius: side / 2)
        // Only the outer edge curves. Beside the physical camera, the small
        // camera gap is enough; mirroring this inset leaves a conspicuous void.
        return inset + stripMarkEdgePadding
    }
    /// Air between the camera and what sits beside it.
    static let stripCameraGap: CGFloat = 6

    static func stripTextSize(height: CGFloat) -> CGFloat { min(15, height - 7) }
    static let stripTextEdgePadding: CGFloat = 8
    static func stripTextOuterInset(geometry: NotchGeometry) -> CGFloat {
        let size = stripTextSize(height: geometry.compactActivityContentHeight)
        let inset = !geometry.compactActivityUsesFooter
            ? geometry.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0) : 0
        return inset + stripTextEdgePadding
    }

    /// What the strip shows beside the camera while agents work: the reading
    /// the person chose, or the time elapsed while that one is unknown.
    static func stripReading(_ snapshot: AgentUsageSnapshot, readout: NotchAgentReadout,
                             display: NotchAgentLimitDisplay, focus: NotchAgentLimitFocus = .mostUsed,
                             now: Date) -> String {
        let live = snapshot.live
        func elapsed() -> String { AgentFormat.clock(now.timeIntervalSince(live.map(\.started).min() ?? now)) }
        switch readout {
        case .elapsed:
            return elapsed()
        case .tokens:
            // What the agent wrote, the count its own window shows; the
            // context it reads again on every call is in the cost.
            return AgentFormat.tokens(live.reduce(0) { $0 + $1.tokens.output })
        case .cost:
            return AgentFormat.cost(live.reduce(0) { $0 + $1.cost })
        case .limit:
            guard let provider = AgentProvider.allCases.first(where: { provider in live.contains { $0.provider == provider } }),
                  let window = focusedLimit(snapshot.limits[provider], focus: focus, now: now) else { return elapsed() }
            return AgentFormat.percent(display == .used ? window.usedFraction : window.remainingFraction)
        }
    }

    /// Every digit takes the same width, so a reading's shape, not its value,
    /// sets the strip's width: "12:34" and "59:59" match, "1:00:00" is wider.
    static func readingShape(_ reading: String) -> String {
        String(reading.map { $0.isNumber ? "0" : $0 })
    }

    // MARK: Layout

    static let spacing: CGFloat = 10
    static let cardHeight: CGFloat = 96
    static let chartHeight: CGFloat = 118
    /// Below this width every card takes a row of its own.
    static let pairWidth: CGFloat = 390

    static func tiles(cards: [NotchAgentCard], providers: [AgentProvider]) -> [NotchAgentTile] {
        var ordered = cards
        if providers.count >= 3, cards.contains(.limits),
           let live = cards.firstIndex(of: .live), let trend = cards.firstIndex(of: .trend), live < trend {
            ordered.remove(at: live)
            ordered.insert(.live, at: trend)
        }
        return ordered.flatMap { card -> [NotchAgentTile] in
            switch card {
            case .limits: return providers.map { NotchAgentTile(card: .limits, provider: $0) }
            // Banked resets belong to a Codex account.
            case .resets: return providers.contains(.codex) ? [NotchAgentTile(card: .resets, provider: .codex)] : []
            default: return [NotchAgentTile(card: card, provider: nil)]
            }
        }
    }

    /// Account-aware and layout-customized tile builder for the revamped AI Agents page.
    static func customizedTiles(cards: [NotchAgentCard],
                                providers: [AgentProvider],
                                accounts: [AgentAccount],
                                config: NotchAgentLayoutConfig) -> [NotchAgentTile] {
        let activeProviders = Set(providers)
        let enabledAccounts = accounts.filter { $0.enabled && activeProviders.contains($0.provider) }
        return cards.flatMap { card -> [NotchAgentTile] in
            let fullWidth = config.isFullWidth(card: card)
            switch card {
            case .limits:
                if config.accountCardMode == .separateAccounts {
                    var result: [NotchAgentTile] = []
                    var coveredProviders = Set<AgentProvider>()
                    var countByProvider: [AgentProvider: Int] = [:]
                    for account in enabledAccounts {
                        countByProvider[account.provider, default: 0] += 1
                    }
                    // Follow the user's explicit account order so rearranging accounts rearranges their cards.
                    for account in enabledAccounts {
                        coveredProviders.insert(account.provider)
                        let multi = (countByProvider[account.provider] ?? 0) > 1
                        let customLabel = multi || account.label != account.provider.displayName ? account.label : nil
                        result.append(NotchAgentTile(
                            card: .limits, provider: account.provider,
                            accountID: account.id,
                            accountLabel: customLabel,
                            accountAccentHex: account.accentHex,
                            customFullWidth: fullWidth))
                    }
                    for provider in providers where !coveredProviders.contains(provider) {
                        result.append(NotchAgentTile(card: .limits, provider: provider, customFullWidth: fullWidth))
                    }
                    return result
                }
                return providers.map { NotchAgentTile(card: .limits, provider: $0, customFullWidth: fullWidth) }
            case .resets:
                return providers.contains(.codex)
                    ? [NotchAgentTile(card: .resets, provider: .codex, customFullWidth: fullWidth)] : []
            default:
                return [NotchAgentTile(card: card, provider: nil, customFullWidth: fullWidth)]
            }
        }
    }

    /// Cards pair up in reading order; a chart, or a card left without a
    /// partner, takes the whole row.
    static func rows(_ tiles: [NotchAgentTile], width: CGFloat,
                     config: NotchAgentLayoutConfig = .default) -> [[NotchAgentTile]] {
        let pairs: Bool
        switch config.columnMode {
        case .auto: pairs = width >= pairWidth
        case .twoColumn: pairs = width >= 280
        case .singleColumn: pairs = false
        }
        var rows: [[NotchAgentTile]] = []
        var waiting: NotchAgentTile?
        for tile in tiles {
            if tile.effectiveFullWidth || !pairs {
                if let waiting { rows.append([waiting]) }
                waiting = nil
                rows.append([tile])
            } else if let partner = waiting {
                rows.append([partner, tile])
                waiting = nil
            } else {
                waiting = tile
            }
        }
        if let waiting { rows.append([waiting]) }
        return rows
    }

    static func height(of row: [NotchAgentTile], config: NotchAgentLayoutConfig = .default) -> CGFloat {
        config.cardHeight(fullWidth: row.contains { $0.effectiveFullWidth })
    }

    /// A full-width live card after a pair can instead occupy the right
    /// column across both rows, leaving the other two cards stacked at left.
    static func liveColumn(at index: Int, rows: [[NotchAgentTile]]) -> Bool {
        rows.indices.contains(index) && rows.indices.contains(index + 1)
            && rows[index].count == 2 && !rows[index].contains { $0.effectiveFullWidth }
            && rows[index + 1].count == 1 && rows[index + 1][0].card == .live
            && !rows[index + 1][0].effectiveFullWidth
    }

    /// With three or more limits cards, keep the trend chart in the initial view.
    static func heightThroughTrend(_ rows: [[NotchAgentTile]]) -> CGFloat {
        guard rows.joined().filter({ $0.card == .limits }).count >= 3,
              let trend = rows.firstIndex(where: { $0.contains { $0.card == .trend } }) else { return 0 }
        return contentHeight(Array(rows[...trend]))
    }

    static func contentHeight(_ rows: [[NotchAgentTile]], config: NotchAgentLayoutConfig = .default) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        return rows.map { height(of: $0, config: config) }.reduce(0, +) + spacing * CGFloat(rows.count - 1)
    }
}

/// Numbers in the reader's region; costs in US dollars, the currency both
/// providers list their prices in.
enum AgentFormat {
    static func cost(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "$0" }
        let magnitude = abs(value)
        if magnitude >= 10_000 { return "$" + scaled(magnitude / 1000, locale: locale) + "K" }
        let digits = magnitude >= 100 ? 0 : 2
        return "$" + value.formatted(.number.precision(.fractionLength(digits)).grouping(.automatic).locale(locale))
    }

    static func tokens(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let magnitude = Double(max(0, value))
        switch magnitude {
        case ..<1000: return Int(magnitude).formatted(.number.locale(locale))
        case ..<1_000_000: return scaled(magnitude / 1000, locale: locale) + "K"
        case ..<1_000_000_000: return scaled(magnitude / 1_000_000, locale: locale) + "M"
        default: return scaled(magnitude / 1_000_000_000, locale: locale) + "B"
        }
    }

    /// One decimal below ten, none above: "4.2", "48", "120".
    private static func scaled(_ value: Double, locale: Locale) -> String {
        let digits = value < 10 ? 1 : 0
        let rounded = (value * (digits == 1 ? 10 : 1)).rounded(.down) / (digits == 1 ? 10 : 1)
        return rounded.formatted(.number.precision(.fractionLength(0...digits)).locale(locale))
    }

    static func percent(_ fraction: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// "4m 12s", "1h 05m", "2d 3h", in the app's language.
    static func duration(_ seconds: TimeInterval, locale: Locale, units: Int = 2,
                         style: DateComponentsFormatter.UnitsStyle = .abbreviated) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = style
        formatter.maximumUnitCount = units
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: max(0, seconds.isFinite ? seconds : 0)) ?? ""
    }

    /// "13 weeks" or "30 days", spelled out in the app's language.
    static func span(days: Int, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        let weeks = days % 7 == 0
        formatter.allowedUnits = weeks ? [.weekOfMonth] : [.day]
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        // Components, not an interval: an interval is measured from today and
        // can lose a week across a month.
        let count = max(0, days)
        return formatter.string(from: weeks ? DateComponents(weekOfMonth: count / 7) : DateComponents(day: count)) ?? ""
    }

    /// A running stopwatch: "0:42", "12:05", "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// A calendar day kept in UTC, like the price list's, read as that same
    /// day wherever the Mac is.
    static func day(_ date: Date, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        style.timeZone = .gmt
        return date.formatted(style)
    }
}
