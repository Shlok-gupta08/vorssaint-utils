// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Dedicated AI Agents settings pane: multi-account management across providers,
/// interactive Dynamic Island layout designer with live preview, and alerts.
struct AIAgentsSettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case accounts, layout, alerts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .accounts: return "Accounts"
            case .layout: return "Notch Layout"
            case .alerts: return "Alerts & Pricing"
            }
        }
        var symbol: String {
            switch self {
            case .accounts: return "person.2.badge.gearshape"
            case .layout: return "rectangle.3.group"
            case .alerts: return "bell.badge"
            }
        }
    }

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsEnabled) private var agentsEnabled = true
    @AppStorage(DefaultsKey.notchAgentsClaude) private var claude = true
    @AppStorage(DefaultsKey.notchAgentsCodex) private var codex = true
    @AppStorage(DefaultsKey.notchAgentsOpenCode) private var opencode = true
    @AppStorage(DefaultsKey.notchAgentsAntigravity) private var antigravity = true
    @AppStorage(DefaultsKey.notchAgentsCardOrder) private var cardOrder = ""
    @AppStorage(DefaultsKey.notchAgentsHiddenCards) private var hiddenCards = ""
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var limitDisplay = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var limitFocus = NotchAgentLimitFocus.mostUsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLiveActivity) private var liveActivity = true
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsFinishAlert) private var finishAlert = true
    @AppStorage(DefaultsKey.notchAgentsFinishMinimum) private var finishMinimum = NotchAgentSupport.defaultFinishMinimum
    @AppStorage(DefaultsKey.notchAgentsLimitAlert) private var limitAlert = true
    @AppStorage(DefaultsKey.notchAgentsLimitThreshold) private var limitThreshold = NotchAgentSupport.defaultLimitThreshold
    @AppStorage(DefaultsKey.notchAgentsDailyBudget) private var dailyBudget = 0.0
    @AppStorage(DefaultsKey.notchAgentsPriceUpdates) private var priceUpdates = true
    @AppStorage(DefaultsKey.notchAgentsAccounts) private var accountsRaw = ""
    @AppStorage(DefaultsKey.notchAgentsLayoutConfig) private var layoutConfigRaw = ""

    @State private var selectedTab: Tab = .accounts
    @State private var accounts: [AgentAccount] = []
    @State private var layoutConfig: NotchAgentLayoutConfig = .default
    @State private var draggingCard: NotchAgentCard?
    @State private var draggingAccountID: String?
    @State private var showingAddAccount = false
    @State private var editingAccount: AgentAccount?
    @State private var newProvider: AgentProvider = .antigravity
    @State private var newLabel = ""
    @State private var newPath = ""
    @State private var newT3Instance = ""
    @State private var newAccentHex = ""

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    private var orderedCards: [NotchAgentCard] {
        let stored = cardOrder.split(separator: ",").compactMap { NotchAgentCard(rawValue: String($0)) }
        var seen = Set<NotchAgentCard>()
        return (stored + NotchAgentCard.allCases).filter { seen.insert($0).inserted }
    }

    private var enabledProviders: [AgentProvider] {
        [claude ? AgentProvider.claude : nil, codex ? .codex : nil, opencode ? .opencode : nil, antigravity ? .antigravity : nil].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 22)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedTab {
                    case .accounts: accountsSection
                    case .layout: layoutDesignerSection
                    case .alerts: alertsSection
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { reloadState() }
        .onChange(of: [String(agentsEnabled), String(claude), String(codex), String(opencode), String(antigravity),
                       cardOrder, hiddenCards, String(liveActivity), readout, limitDisplay, limitFocus,
                       accountsRaw, layoutConfigRaw]) { _, _ in
            AgentUsageService.shared.syncWithPreferences()
            NotchService.shared.syncWithPreferences()
        }
        .sheet(isPresented: $showingAddAccount) { accountEditorSheet(existing: nil) }
        .sheet(item: $editingAccount) { account in accountEditorSheet(existing: account) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Agents")
                    .font(.title2.bold())
                Text("Multi-account detection, custom Dynamic Island layouts, and live usage tracking.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enable AI Agents", isOn: $agentsEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    // MARK: - Tab 1: Accounts & Providers

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Providers") {
                HStack(spacing: 10) {
                    providerPill(.claude, isOn: $claude)
                    providerPill(.codex, isOn: $codex)
                    providerPill(.antigravity, isOn: $antigravity)
                    providerPill(.opencode, isOn: $opencode)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Account card display")
                            .font(.subheadline.weight(.medium))
                        Text("Show an individual limits card per account or combine accounts under each provider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { layoutConfig.accountCardMode },
                        set: { layoutConfig.accountCardMode = $0; persistLayout() }
                    )) {
                        ForEach(NotchAgentLayoutConfig.AccountCardMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            SettingsCard(title: "Configured Accounts") {
                HStack {
                    Text("\(accounts.filter(\.enabled).count) active across \(Set(accounts.filter(\.enabled).map(\.provider)).count) providers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        rescanAccounts()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    Button {
                        newProvider = .antigravity
                        newLabel = ""
                        newPath = ""
                        newT3Instance = ""
                        newAccentHex = ""
                        showingAddAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if accounts.isEmpty {
                    Text("No local agent accounts detected yet. Click Add Account to point Vorssaint to any Codex, Claude, Antigravity, or OpenCode profile directory.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                            accountRow(account, index: index)
                        }
                    }
                }
            }
        }
    }

    private func providerPill(_ provider: AgentProvider, isOn: Binding<Bool>) -> some View {
        let activeCount = [claude, codex, opencode, antigravity].filter { $0 }.count
        return Button {
            if isOn.wrappedValue && activeCount <= 1 { return }
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 7) {
                NotchAgentMark(provider: provider, size: 12)
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn.wrappedValue ? provider.tint : .secondary)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                isOn.wrappedValue ? provider.tint.opacity(0.12) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isOn.wrappedValue ? provider.tint.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func accountRow(_ account: AgentAccount, index: Int) -> some View {
        let isLive = usage.snapshot.live.contains { $0.accountID == account.id || ($0.provider == account.provider && $0.accountLabel == account.label) }
        let hasQuota = usage.snapshot.accountLimits[account.id] != nil
        let tint = account.customColor ?? account.provider.tint
        return HStack(spacing: 10) {
            PanelDragHandle()
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 30, height: 30)
                NotchAgentMark(provider: account.provider, size: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.label)
                        .font(.subheadline.weight(.semibold))
                    Text(account.provider.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(tint.opacity(0.13), in: Capsule())
                    if isLive {
                        HStack(spacing: 3) {
                            Circle().fill(.green).frame(width: 5, height: 5)
                            Text("Running")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.green.opacity(0.14), in: Capsule())
                    } else if hasQuota {
                        Text("Quota Synced")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    if let t3 = account.t3InstanceID, !t3.isEmpty {
                        Text("T3: \(t3)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if !account.sourcePath.isEmpty {
                        Text(abbreviatePath(account.sourcePath))
                            .font(.caption2)
                            .foregroundStyle(account.existsOnDisk ? Color.secondary : Color.orange)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                    Button { moveAccount(at: index, by: -1) } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == 0 ? .quaternary : .secondary)
                    .disabled(index == 0)
                    .help("Move up")

                    Button { moveAccount(at: index, by: 1) } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index >= accounts.count - 1 ? .quaternary : .secondary)
                    .disabled(index >= accounts.count - 1)
                    .help("Move down")

                Button {
                    newProvider = account.provider
                    newLabel = account.label
                    newPath = account.sourcePath
                    newT3Instance = account.t3InstanceID ?? ""
                    newAccentHex = account.accentHex ?? ""
                    editingAccount = account
                } label: {
                    Image(systemName: "pencil").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Edit account")

                if !account.isAutoDiscovered {
                    Button(role: .destructive) {
                        accounts.removeAll { $0.id == account.id }
                        persistAccounts()
                    } label: {
                        Image(systemName: "trash").font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("Remove custom account")
                }

                Toggle("", isOn: Binding(
                    get: { account.enabled },
                    set: { enabled in
                        if let i = accounts.firstIndex(where: { $0.id == account.id }) {
                            accounts[i].enabled = enabled
                            persistAccounts()
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(draggingAccountID == account.id ? 0.5 : 1)
        .onDrag {
            draggingAccountID = account.id
            return NSItemProvider(object: account.id as NSString)
        }
        .onDrop(of: [UTType.text], delegate: AgentAccountDropDelegate(
            targetID: account.id,
            accounts: $accounts,
            draggingID: $draggingAccountID,
            onReorder: { persistAccounts() }
        ))
    }

    // MARK: - Tab 2: Interactive Notch Layout Designer

    private var layoutDesignerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Live Notch Preview") {
                notchLayoutPreview
                HStack(spacing: 8) {
                    Text("Presets:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    ForEach(NotchAgentLayoutConfig.Preset.allCases) { preset in
                        Button(preset.title) {
                            NotchAgentLayoutConfig.applyPreset(preset)
                            layoutConfig = NotchAgentLayoutConfig.current()
                            cardOrder = UserDefaults.standard.string(forKey: DefaultsKey.notchAgentsCardOrder) ?? ""
                            hiddenCards = UserDefaults.standard.string(forKey: DefaultsKey.notchAgentsHiddenCards) ?? ""
                        }
                        .controlSize(.small)
                    }
                    Spacer()
                }
            }

            SettingsCard(title: "Grid & Density") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Columns").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { layoutConfig.columnMode },
                            set: { layoutConfig.columnMode = $0; persistLayout() }
                        )) {
                            ForEach(NotchAgentLayoutConfig.ColumnMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Card Height").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { layoutConfig.density },
                            set: { layoutConfig.density = $0; persistLayout() }
                        )) {
                            ForEach(NotchAgentLayoutConfig.Density.allCases) { d in
                                Text(d.title).tag(d)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                Divider()

                SettingsChoiceRow(symbol: NotchAgentCard.limits.symbol, title: text.limitsAs, selection: $limitDisplay) {
                    Text(text.remaining).tag(NotchAgentLimitDisplay.remaining.rawValue)
                    Text(text.used).tag(NotchAgentLimitDisplay.used.rawValue)
                }
                SettingsMenuRow(symbol: "rectangle.topthird.inset.filled", title: text.limitFocus, selection: $limitFocus) {
                    ForEach(NotchAgentLimitFocus.allCases) { focus in
                        Text(text.limitFocus(focus)).tag(focus.rawValue)
                    }
                }
            }

            SettingsCard(title: "Card Order & Span") {
                Text("Drag cards (or use arrows) to rearrange the Dynamic Island layout, toggle visibility, and choose half width (1×) or full width (2×).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    let orderBinding = Binding<[NotchAgentCard]>(
                        get: { orderedCards },
                        set: { newOrder in
                            cardOrder = newOrder.map(\.rawValue).joined(separator: ",")
                        }
                    )
                    ForEach(Array(orderedCards.enumerated()), id: \.element.id) { index, card in
                        let shown = cardBinding(card)
                        let isFull = layoutConfig.isFullWidth(card: card)
                        PanelReorderableItem(item: card, order: orderBinding, dragging: $draggingCard) {
                            HStack(spacing: 10) {
                                PanelDragHandle()
                                Image(systemName: card.symbol)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(shown.wrappedValue ? Color.accentColor : .secondary)
                                    .frame(width: 24, height: 24)
                                    .background((shown.wrappedValue ? Color.accentColor : Color.secondary).opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(text.card(card))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(shown.wrappedValue ? .primary : .secondary)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { isFull },
                                    set: { layoutConfig.setFullWidth($0, for: card); persistLayout() }
                                )) {
                                    Text("1×").tag(false)
                                    Text("2× Full").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 112)
                                .disabled(!shown.wrappedValue || layoutConfig.columnMode == .singleColumn)

                                Button { moveCard(card, by: -1) } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 10, weight: .semibold))
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(index == 0 ? .quaternary : .secondary)
                                .disabled(index == 0)
                                .help("Move up")

                                Button { moveCard(card, by: 1) } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(index >= orderedCards.count - 1 ? .quaternary : .secondary)
                                .disabled(index >= orderedCards.count - 1)
                                .help("Move down")

                                Toggle("", isOn: shown)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .opacity(draggingCard == card ? 0.5 : 1)
                        }
                    }
                }
            }

            SettingsCard(title: "Live Activity Pill") {
                SettingsRow(symbol: "waveform.path.ecg", title: text.liveActivity) {
                    Toggle(text.liveActivity, isOn: $liveActivity).labelsHidden().toggleStyle(.switch)
                }
                if liveActivity {
                    SettingsMenuRow(symbol: "camera.metering.center.weighted", title: text.readout, selection: $readout) {
                        ForEach(NotchAgentReadout.allCases) { option in
                            Text(text.readout(option)).tag(option.rawValue)
                        }
                    }
                    SettingsRow(symbol: "tag", title: "Show account label on active sessions") {
                        Toggle("", isOn: Binding(
                            get: { layoutConfig.showAccountLabelInPill },
                            set: { layoutConfig.showAccountLabelInPill = $0; persistLayout() }
                        )).labelsHidden().toggleStyle(.switch)
                    }
                }
            }
        }
    }

    private var notchLayoutPreview: some View {
        let previewProviders = enabledProviders.isEmpty ? [AgentProvider.antigravity, .codex] : enabledProviders
        let hiddenSet = Set(hiddenCards.split(separator: ",").map(String.init))
        let visibleCards = orderedCards.filter { !hiddenSet.contains($0.rawValue) }
        let tiles = NotchAgentSupport.customizedTiles(
            cards: visibleCards,
            providers: previewProviders,
            accounts: accounts,
            config: layoutConfig
        )
        let previewRows = NotchAgentSupport.rows(tiles, width: 460, config: layoutConfig)
        let orderBinding = Binding<[NotchAgentCard]>(
            get: { orderedCards },
            set: { newOrder in
                cardOrder = newOrder.map(\.rawValue).joined(separator: ",")
            }
        )
        return VStack(spacing: 0) {
            // Notch top bar silhouette
            HStack {
                Text("AI Agents")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Capsule().fill(.black).frame(width: 72, height: 14)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                Spacer()
                Text("Drag to reorder · Click to resize")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            VStack(spacing: 6) {
                ForEach(Array(previewRows.prefix(5).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row) { tile in
                            let tint = tile.provider?.tint ?? Color.white
                            PanelReorderableItem(item: tile.card, order: orderBinding, dragging: $draggingCard) {
                                HStack(spacing: 6) {
                                    Image(systemName: tile.card.symbol)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(tint)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tile.accountLabel ?? tile.provider?.displayName ?? text.card(tile.card))
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(tile.effectiveFullWidth ? "Full width" : "Half width")
                                            .font(.system(size: 8.5))
                                            .foregroundStyle(.white.opacity(0.45))
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 9)
                                .frame(maxWidth: .infinity)
                                .frame(height: layoutConfig.density == .compact ? 32 : 40)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(tint.opacity(0.24), lineWidth: 0.75))
                                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .onTapGesture {
                                    guard layoutConfig.columnMode != .singleColumn else { return }
                                    layoutConfig.setFullWidth(!layoutConfig.isFullWidth(card: tile.card), for: tile.card)
                                    persistLayout()
                                }
                            }
                        }
                    }
                }
                if previewRows.count > 5 {
                    Text("+ \(previewRows.count - 5) more row(s) scrollable")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }

    // MARK: - Tab 3: Alerts & Pricing

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: text.alerts) {
                SettingsRow(symbol: "checkmark.circle", title: text.finishAlert) {
                    Toggle(text.finishAlert, isOn: $finishAlert).labelsHidden().toggleStyle(.switch)
                }
                if finishAlert {
                    SettingsMenuRow(symbol: "timer", title: text.finishAfter, selection: $finishMinimum) {
                        ForEach(NotchAgentSupport.finishMinimums, id: \.self) { seconds in
                            Text(seconds == 0 ? text.anyLength : AgentFormat.duration(seconds, locale: locale, style: .short))
                                .tag(seconds)
                        }
                    }
                }
                Divider()
                SettingsRow(symbol: "exclamationmark.triangle", title: text.limitAlert) {
                    Toggle(text.limitAlert, isOn: $limitAlert).labelsHidden().toggleStyle(.switch)
                }
                if limitAlert {
                    SettingsMenuRow(symbol: "gauge.with.dots.needle.67percent", title: text.limitAt, selection: $limitThreshold) {
                        ForEach(NotchAgentSupport.limitThresholds, id: \.self) { value in
                            Text(text.usedShare(AgentFormat.percent(value / 100))).tag(value)
                        }
                    }
                }
                Divider()
                SettingsMenuRow(symbol: "dollarsign.circle", title: text.budget, selection: $dailyBudget) {
                    ForEach(NotchAgentSupport.budgets, id: \.self) { value in
                        Text(value == 0 ? text.off : AgentFormat.cost(value)).tag(value)
                    }
                }
            }

            SettingsCard(title: "Pricing") {
                SettingsRow(symbol: "arrow.triangle.2.circlepath", title: text.priceUpdates, caption: text.priceUpdatesHint) {
                    Toggle(text.priceUpdates, isOn: $priceUpdates).labelsHidden().toggleStyle(.switch)
                }
                Text(text.valueNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Add / Edit Account Sheet

    private func accountEditorSheet(existing: AgentAccount?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "Add Agent Account" : "Edit Account")
                .font(.headline)

            Form {
                if existing == nil {
                    Picker("Provider", selection: $newProvider) {
                        ForEach(AgentProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                }
                TextField("Display Name", text: $newLabel, prompt: Text("e.g. Antigravity Work, Personal Codex"))
                HStack {
                    TextField("Profile / Config Folder", text: $newPath, prompt: Text("~/.codex or T3 provider folder"))
                    Button("Browse…") { pickFolder() }
                }
                TextField("T3 Instance ID (optional)", text: $newT3Instance, prompt: Text("e.g. antigravity_antigravity_2"))
                HStack(spacing: 8) {
                    Text("Accent")
                    Spacer()
                    ForEach(["", "5E5CE6", "34C759", "FF9F0A", "0A84FF", "FF375F", "64D2FF"], id: \.self) { hex in
                        Button {
                            newAccentHex = hex
                        } label: {
                            Circle()
                                .fill(hex.isEmpty ? newProvider.tint : colorFromHex(hex))
                                .frame(width: 18, height: 18)
                                .overlay {
                                    if newAccentHex == hex {
                                        Circle().strokeBorder(.white, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(hex.isEmpty ? "Provider default" : "#\(hex)")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    showingAddAccount = false
                    editingAccount = nil
                }
                .keyboardShortcut(.cancelAction)

                Button(existing == nil ? "Add" : "Save") {
                    let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedLabel = label.isEmpty ? newProvider.displayName : label
                    let t3 = newT3Instance.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hex = newAccentHex.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let existing, let idx = accounts.firstIndex(where: { $0.id == existing.id }) {
                        accounts[idx].label = resolvedLabel
                        accounts[idx].sourcePath = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        accounts[idx].t3InstanceID = t3.isEmpty ? nil : t3
                        accounts[idx].accentHex = hex.isEmpty ? nil : hex
                    } else {
                        let created = AgentAccount(
                            id: "custom:\(newProvider.rawValue):\(UUID().uuidString.prefix(8))",
                            provider: newProvider,
                            label: resolvedLabel,
                            sourcePath: newPath.trimmingCharacters(in: .whitespacesAndNewlines),
                            t3InstanceID: t3.isEmpty ? nil : t3,
                            enabled: true,
                            accentHex: hex.isEmpty ? nil : hex,
                            isAutoDiscovered: false
                        )
                        accounts.append(created)
                    }
                    persistAccounts()
                    showingAddAccount = false
                    editingAccount = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    // MARK: - Helpers

    private func reloadState() {
        accounts = AgentAccountRegistry.accounts()
        layoutConfig = NotchAgentLayoutConfig.current()
    }

    private func rescanAccounts() {
        let fresh = AgentAccountRegistry.discovered()
        var merged = accounts
        for discovered in fresh where !merged.contains(where: { $0.id == discovered.id }) {
            merged.append(discovered)
        }
        accounts = merged
        persistAccounts()
        AgentUsageService.shared.pageDidAppear()
    }

    private func persistAccounts() {
        AgentAccountRegistry.save(accounts)
        accountsRaw = UserDefaults.standard.string(forKey: DefaultsKey.notchAgentsAccounts) ?? ""
    }

    private func persistLayout() {
        layoutConfig.save()
        layoutConfigRaw = UserDefaults.standard.string(forKey: DefaultsKey.notchAgentsLayoutConfig) ?? ""
    }

    private func moveAccount(at index: Int, by offset: Int) {
        let target = index + offset
        guard accounts.indices.contains(index), accounts.indices.contains(target) else { return }
        accounts.swapAt(index, target)
        persistAccounts()
    }

    private func cardBinding(_ card: NotchAgentCard) -> Binding<Bool> {
        Binding {
            !hiddenCards.split(separator: ",").contains(Substring(card.rawValue))
        } set: { shown in
            var hidden = Set(hiddenCards.split(separator: ",").map(String.init))
            if shown { hidden.remove(card.rawValue) } else { hidden.insert(card.rawValue) }
            hiddenCards = hidden.sorted().joined(separator: ",")
        }
    }

    private func moveCard(_ card: NotchAgentCard, by offset: Int) {
        var order = orderedCards
        guard let index = order.firstIndex(of: card), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        cardOrder = order.map(\.rawValue).joined(separator: ",")
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            newPath = url.path
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func colorFromHex(_ hex: String) -> Color {
        guard let value = UInt64(hex, radix: 16) else { return .accentColor }
        return Color(.sRGB,
                     red: Double((value >> 16) & 0xFF) / 255.0,
                     green: Double((value >> 8) & 0xFF) / 255.0,
                     blue: Double(value & 0xFF) / 255.0,
                     opacity: 1)
    }
}

private struct AgentAccountDropDelegate: DropDelegate {
    let targetID: String
    @Binding var accounts: [AgentAccount]
    @Binding var draggingID: String?
    let onReorder: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID,
              let from = accounts.firstIndex(where: { $0.id == draggingID }),
              let to = accounts.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            accounts.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        onReorder()
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
