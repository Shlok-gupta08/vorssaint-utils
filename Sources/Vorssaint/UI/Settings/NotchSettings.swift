// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import EventKit

struct NotchSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var router = SettingsRouter.shared
    @AppStorage(DefaultsKey.notchGesturesEnabled) private var gesturesEnabled = true
    @AppStorage(DefaultsKey.notchKeyboardLight) private var keyboardLight = true
    @AppStorage(DefaultsKey.notchNotificationsEnabled) private var notificationsEnabled = true
    @AppStorage(DefaultsKey.notchDismissNativeNotifications) private var dismissNativeNotifications = false
    @AppStorage(DefaultsKey.notchTimerEnabled) private var timerEnabled = true
    @AppStorage(DefaultsKey.notchTimerSoundEnabled) private var timerSoundEnabled = true
    @AppStorage(DefaultsKey.notchCameraEnabled) private var cameraEnabled = true
    @AppStorage(DefaultsKey.notchAccessoriesEnabled) private var accessoriesEnabled = true
    @AppStorage(DefaultsKey.notchCalendarEnabled) private var calendarEnabled = true
    @AppStorage(DefaultsKey.notchCalendarCountdown) private var calendarCountdown = false
    @AppStorage(DefaultsKey.notchCalendarTimeLeft) private var calendarTimeLeft = false
    @AppStorage(DefaultsKey.notchAgentsEnabled) private var agentsEnabled = true
    @AppStorage(DefaultsKey.notchTeleprompterEnabled) private var teleprompterEnabled = true
    @AppStorage(DefaultsKey.notchRecordingLiveActivity) private var recordingLiveActivity = true
    @AppStorage(DefaultsKey.notchFocusEnabled) private var focusEnabled = true
    @AppStorage(DefaultsKey.notchFocusHideNative) private var focusHideNative = true
    @AppStorage(DefaultsKey.notchShortcutsEnabled) private var shortcutsEnabled = true
    @AppStorage(DefaultsKey.notchCallsEnabled) private var callsEnabled = false
    @AppStorage(DefaultsKey.notchWatchEnabled) private var watchEnabled = true
    @AppStorage(DefaultsKey.notchLyricsEnabled) private var lyricsEnabled = true
    @AppStorage(DefaultsKey.notchLyricsOnline) private var lyricsOnline = false
    @AppStorage(DefaultsKey.notchQueueEnabled) private var queueEnabled = true
    @AppStorage(DefaultsKey.notchLiveEqualizer) private var liveEqualizer = false
    @AppStorage(DefaultsKey.notchEnabled) private var enabled = false
    @AppStorage(DefaultsKey.notchDisplay) private var display = NotchDisplay.automatic.rawValue
    @AppStorage(DefaultsKey.notchDisplayPreferences) private var displayPreferences = ""
    @AppStorage(DefaultsKey.notchPreferredDisplay) private var preferredDisplay = ""
    @AppStorage(DefaultsKey.notchSilhouette) private var silhouette = NotchSilhouette.capsule.rawValue
    @AppStorage(DefaultsKey.notchOpenOnHover) private var hover = false
    @AppStorage(DefaultsKey.notchHideInFullscreen) private var hideInFullscreen = false
    @AppStorage(DefaultsKey.notchHideUntilHover) private var hideUntilHover = false
    @AppStorage(DefaultsKey.notchAutoHideWithoutNotch) private var autoHideWithoutNotch = true
    @AppStorage(DefaultsKey.notchCoversMenus) private var coversMenus = true
    @AppStorage(DefaultsKey.notchHoverDelay) private var hoverDelay = NotchSupport.defaultHoverDelay
    @AppStorage(DefaultsKey.notchReturnHome) private var returnHome = false
    @AppStorage(DefaultsKey.notchHomeModule) private var homeModule = NotchModule.controls.rawValue
    @AppStorage(DefaultsKey.notchOpensActivity) private var opensActivity = true
    @AppStorage(DefaultsKey.notchHiddenModules) private var hidden = ""
    @AppStorage(DefaultsKey.notchModuleOrder) private var order = ""
    @AppStorage(DefaultsKey.notchVolume) private var volume = true
    @AppStorage(DefaultsKey.notchMicrophone) private var microphone = true
    @AppStorage(DefaultsKey.notchBrightness) private var brightness = true
    @AppStorage(DefaultsKey.notchBattery) private var battery = true
    @AppStorage(DefaultsKey.notchClipboard) private var clipboard = true
    @AppStorage(DefaultsKey.notchClipboardWindow) private var clipboardWindow = true
    @AppStorage(DefaultsKey.screenshotDefaultAction) private var captureAction = ""
    @AppStorage(DefaultsKey.notchCapture) private var capture = true
    @AppStorage(DefaultsKey.notchTrackChange) private var trackChange = true
    @AppStorage(DefaultsKey.notchShowPlayingMusic) private var showPlayingMusic = true
    @AppStorage(DefaultsKey.notchHideMusicWhenPlayerActive) private var hideMusicWhenPlayerActive = false
    @AppStorage(DefaultsKey.notchMusicPauseTimeout) private var musicPauseTimeout = 5.0
    @AppStorage(DefaultsKey.notchIncludeOtherPlayers) private var includeOtherPlayers = false
    @AppStorage(DefaultsKey.notchIdleContent) private var idle = NotchIdleContent.music.rawValue
    @AppStorage(DefaultsKey.notchHiddenControls) private var hiddenControls = NotchControlItem.defaultHidden
    @AppStorage(DefaultsKey.notchControlOrder) private var controlOrder = ""
    @AppStorage(DefaultsKey.notchShowInCaptures) private var showInCaptures = true
    @AppStorage(DefaultsKey.notchLockScreen) private var lockScreen = false
    @AppStorage(DefaultsKey.notchLockSounds) private var lockSounds = false
    @AppStorage(DefaultsKey.notchSize) private var size = NotchSize.spacious.rawValue
    @AppStorage(DefaultsKey.notchExpandedScale) private var expandedScale = NotchSize.defaultExpandedScale
    @AppStorage(DefaultsKey.notchOutlineEnabled) private var outlineEnabled = false
    @AppStorage(DefaultsKey.notchCustomWidth) private var customWidth = NotchSize.defaultWidth
    @AppStorage(DefaultsKey.notchCustomHeight) private var customHeight = NotchSize.defaultHeight
    @AppStorage(DefaultsKey.notchCameraFitWidth) private var cameraFitWidth = 0.0
    @AppStorage(DefaultsKey.notchCameraFitHeight) private var cameraFitHeight = 0.0
    @AppStorage(DefaultsKey.notchCapsuleFitWidth) private var capsuleFitWidth = 0.0
    @AppStorage(DefaultsKey.notchCapsuleFitHeight) private var capsuleFitHeight = 0.0
    @AppStorage(DefaultsKey.notchCapsuleFitDrop) private var capsuleFitDrop = 0.0
    @AppStorage(DefaultsKey.notchHapticFeedback) private var hapticFeedback = true
    @AppStorage(DefaultsKey.notchTranslucentBackground) private var translucentBackground = false
    @AppStorage(DefaultsKey.notchLiquidGlassEnabled) private var liquidGlass = false
    @AppStorage(DefaultsKey.notchShelf) private var shelfWindow = true
    @AppStorage(DefaultsKey.notchDragReveal) private var dragReveal = true
    @AppStorage(DefaultsKey.notchCaptureControls) private var captureControls = true
    @AppStorage(DefaultsKey.notchQuickPanel) private var quickPanel = true
    @AppStorage(DefaultsKey.notchAppPanel) private var appPanel = false
    @AppStorage(DefaultsKey.notchHidesMenuBarIcon) private var hidesMenuBarIcon = false
    @AppStorage(DefaultsKey.notchKeepAwakeActivity) private var keepAwakeActivity = false
    @AppStorage(DefaultsKey.notchScratchpad) private var scratchpad = true
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessControlEnabled = false
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var clipboardHistoryEnabled = false
    @AppStorage(DefaultsKey.notchHoverExpands) private var hoverExpand = true
    @AppStorage(DefaultsKey.notchQuickAccessLayout) private var accessData = Data()
    @State private var connectedScreens = NSScreen.screens
    @State private var tab = NotchSettingsTab.overview
    @State private var settingsQuery = ""
    @State private var controlQuery = ""
    @State private var pageQuery = ""
    @State private var selectedModule = NotchModule.controls
    @State private var draggingModule: NotchModule?
    @State private var draggingControl: NotchControlItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }

    init(section: NotchSettingsTab = .overview, query: String = "") {
        _tab = State(initialValue: section)
        _settingsQuery = State(initialValue: query)
    }

    private var configuration: [String] {
        [String(enabled), String(shortcutsEnabled), String(callsEnabled), String(calendarEnabled), String(calendarCountdown), String(calendarTimeLeft), String(notificationsEnabled), String(dismissNativeNotifications), String(gesturesEnabled), String(lyricsEnabled), String(lyricsOnline), String(queueEnabled), String(liveEqualizer), String(showPlayingMusic), String(hideMusicWhenPlayerActive), String(includeOtherPlayers), idle, hiddenControls, controlOrder, size,
         String(timerEnabled), String(timerSoundEnabled), String(cameraEnabled), String(accessoriesEnabled), String(outlineEnabled), String(customWidth), String(customHeight), String(cameraFitWidth), String(cameraFitHeight), String(capsuleFitWidth), String(capsuleFitHeight), String(capsuleFitDrop), String(hapticFeedback), String(shelfWindow), String(dragReveal), String(captureControls), String(quickPanel), String(appPanel), String(hoverExpand), String(hideUntilHover), String(autoHideWithoutNotch), String(hideInFullscreen), String(coversMenus), display, displayPreferences, preferredDisplay, silhouette, String(hover), hidden, order, String(volume),
         String(brightness), String(keyboardLight), String(microphone), String(battery), String(clipboard), String(clipboardWindow), String(capture), String(trackChange), captureAction, String(showInCaptures), String(returnHome), homeModule, String(opensActivity), String(scratchpad), String(agentsEnabled), String(watchEnabled), String(keepAwakeActivity), String(expandedScale), String(teleprompterEnabled), String(recordingLiveActivity), String(focusEnabled), String(focusHideNative)]
    }

    private var access: Binding<NotchQuickAccessConfiguration> {
        Binding(get: { NotchQuickAccessConfiguration.stored() }, set: { accessData = $0.encoded })
    }

    private var orderedModules: [NotchModule] {
        let stored = order.split(separator: ",").compactMap { NotchModule(rawValue: String($0)) }
        var seen = Set<NotchModule>()
        return (stored + NotchModule.allCases).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(text.title).font(.title2.bold())
                    if tab == .overview {
                        Text(text.description).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                Spacer(minLength: 12)
                Button { NotchService.shared.open() } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.bordered).disabled(!enabled).help(text.open).accessibilityLabel(text.open)
                Toggle(text.enable, isOn: $enabled).labelsHidden().toggleStyle(.switch)
                    .disabled(!AppFeature.notch.isAvailable).accessibilityLabel(text.enable)
            }
            if enabled, AppFeature.notch.isAvailable, !(hover && hideUntilHover), !autoHideWithoutNotch,
               !notch.geometry.isNotched, !permissions.accessibility {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text.menuBarAccessHint)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PermissionRow(kind: .accessibility)
                }
            }
            TextField("\(l10n.s.settingsSearchPlaceholder) · \(text.title)", text: $settingsQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("notch.settings.search")
            workspaceNavigation
            if NotchSettingsWorkspace.containing(tab).sections.count > 1 && settingsQuery.isEmpty {
                HStack(spacing: 8) {
                    ForEach(NotchSettingsWorkspace.containing(tab).sections) { section in
                        Button { tab = section } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(section.title(l10n.language), systemImage: section.symbol).font(.headline)
                                Text(section.detail(l10n.language)).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(12)
                            .background(tab == section ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(tab == section ? Color.accentColor.opacity(0.5) : .clear) }
                        }.buttonStyle(NotchSettingsButtonStyle()).accessibilityAddTraits(tab == section ? .isSelected : [])
                    }
                }
            }
            GeometryReader { proxy in
                if !settingsQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    settingsSearchResults
                } else {
                    settingsDetail
                }
            }

        }
        .disclosureGroupStyle(NotchSettingsDisclosureStyle())
        .padding(.horizontal, 22).padding(.top, 22)
        .onChange(of: configuration) { _, _ in sync() }
        .onChange(of: accessData) { _, _ in NotchService.shared.syncWithPreferences() }
        .onChange(of: tab) { _, _ in draggingModule = nil; draggingControl = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            connectedScreens = NSScreen.screens
        }
        .onAppear(perform: consumeModuleHint)
        .onChange(of: router.notchModule) { _, _ in consumeModuleHint() }
    }

    @ViewBuilder private var settingsDetail: some View {
        if tab == .content {
            GeometryReader { proxy in contentEditor(in: proxy.size) }
        } else {
            pageScroll
        }
    }

    private var workspaceNavigation: some View {
        NotchSettingsColumns(minimumWidth: 140, maximumColumns: 6) {
            ForEach(NotchSettingsWorkspace.allCases) { group in
                let selected = NotchSettingsWorkspace.containing(tab) == group
                NotchSettingsNavigationButton(title: group.title(l10n.language), symbol: group.symbol, selected: selected) {
                    tab = group.sections[0]; settingsQuery = ""
                }
                    .accessibilityIdentifier("notch.workspace.\(group.rawValue)")
            }
        }
    }

    private var settingsSearchResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !NotchSettingsTab.allCases.contains(where: { $0.matches(settingsQuery, language: l10n.language) })
                    && !NotchModule.allCases.contains(where: moduleMatchesSearch) {
                    Text(FeatureStrings.clipboard(l10n.language).noResults).foregroundStyle(.secondary).padding(.vertical, 24)
                }
                ForEach(NotchSettingsTab.allCases.filter { $0.matches(settingsQuery, language: l10n.language) }) { section in
                    navigationCard(section)
                }
                ForEach(NotchModule.allCases.filter(moduleMatchesSearch)) { module in
                    Button { selectedModule = module; tab = .content; settingsQuery = "" } label: {
                        Label(module.title(l10n.language) + " · " + NotchSettingsTab.content.title(l10n.language), systemImage: module.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(NotchSettingsButtonStyle())
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func moduleMatchesSearch(_ module: NotchModule) -> Bool {
        let value = module.title(l10n.language) + " " + editor.summary(module)
        return settingsQuery.split(whereSeparator: \.isWhitespace).allSatisfy { value.localizedStandardContains(String($0)) }
    }

    private func navigationCard(_ section: NotchSettingsTab) -> some View {
        Button { tab = section; settingsQuery = "" } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: section.symbol).font(.system(size: 19)).foregroundStyle(Color.accentColor).frame(width: 26)
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title(l10n.language)).font(.headline)
                    Text(section.detail(l10n.language)).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 66, alignment: .leading).padding(16)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(NotchSettingsButtonStyle())
    }

    private var overviewPage: some View {
        NotchSettingsColumns(maximumColumns: 2) {
            SettingsCard(title: "Where it appears") {
                HStack {
                    NotchDisplayIllustration(physical: notch.geometry.isNotched,
                        silhouette: NotchSilhouette(rawValue: silhouette) ?? .capsule, enabled: enabled)
                        .frame(width: 212, height: 118).scaleEffect(0.65).frame(width: 140, height: 80)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(connectedScreens.count) connected display\(connectedScreens.count == 1 ? "" : "s")").font(.headline)
                        Text("Each screen keeps its own shape and activity preferences.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                navigationCard(.displays)
            }
            SettingsCard(title: "How it opens") {
                switchRow("cursorarrow", editor.hoverExpand, caption: "Open on hover, or turn this off to use a click.", isOn: Binding(get: { hover && hoverExpand }, set: { hover = $0; hoverExpand = $0; hideUntilHover = false }))
                switchRow("waveform.path", text.hapticFeedback, isOn: $hapticFeedback)
                navigationCard(.behavior)
            }
            SettingsCard(title: "What stays visible") {
                switchRow("music.note", text.playingMusic, isOn: $showPlayingMusic)
                switchRow("bell", NotchModule.notifications.title(l10n.language), isOn: moduleBinding(.notifications))
                    .disabled(!AppFeature.notchNotifications.isAvailable)
                navigationCard(.activity)
            }
            SettingsCard(title: "Make it yours") {
                navigationCard(.content)
                navigationCard(.shortcuts)
                navigationCard(.layout)
            }
        }
    }

    private var pageScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if tab != .overview && NotchSettingsWorkspace.containing(tab).sections.count == 1 {
                    Label(tab.title(l10n.language), systemImage: tab.symbol).font(.title3.bold())
                    Text(tab.detail(l10n.language)).font(.callout).foregroundStyle(.secondary)
                }
                Group {
                    switch tab {
                    case .overview: overviewPage
                    case .layout: layoutPage
                    case .displays: displaysPage
                    case .content: EmptyView()
                    case .shortcuts: extensionsPage
                    case .activity: activityPage
                    case .notifications: notificationsPage
                    case .behavior: behaviorPage
                    case .routing: routingPage
                    case .privacy: privacyPage
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 22)
        }.id(tab)
    }

    private var extensionsPage: some View {
        NotchLayoutEditor(configuration: access, size: $size, width: $customWidth, height: $customHeight) {
            selectedModule = .controls; tab = .content
        }
    }

    /// A section of the island can ask for its own options; the hint is one-shot.
    private func consumeModuleHint() {
        guard let module = router.notchModule else { return }
        router.notchModule = nil
        selectedModule = module
        settingsQuery = ""
        tab = .content
    }

    private func sync() {
        NotchService.shared.syncWithPreferences()
        if !NotchLyricsSupport.isEnabled() { NotchLyricsService.shared.stop() }
        NotchMusicService.shared.syncQueuePreference()
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
    }

    private var layoutPage: some View {
        NotchSettingsColumns {
            SettingsCard(title: text.size) {
                expandedSizeSlider
                Divider()
                HStack(spacing: 10) {
                    choice(text.compact, symbol: "rectangle.compress.vertical", selected: size == NotchSize.compact.rawValue) { size = NotchSize.compact.rawValue }
                    choice(text.spacious, symbol: "rectangle.expand.vertical", selected: size == NotchSize.spacious.rawValue) { size = NotchSize.spacious.rawValue }
                    choice(text.custom, symbol: "arrow.up.left.and.arrow.down.right", selected: size == NotchSize.custom.rawValue) { size = NotchSize.custom.rawValue }
                }
                if size == NotchSize.custom.rawValue {
                    // One grid starts both sliders at the same edge in every language.
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        dimensionSlider(text.width, value: $customWidth, range: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
                        dimensionSlider(text.maximumHeight, value: $customHeight, range: NotchSize.heightRange, fallback: NotchSize.defaultHeight)
                    }
                    Text(text.sizeHint).font(.caption).foregroundStyle(.secondary)
                }
                // Liquid Glass takes the open island's background when it is
                // on and is already see-through, so the switch reads on and
                // changes nothing then.
                switchRow("drop.halffull", text.translucentBackground,
                          caption: liquidGlassIsOn ? text.translucentBackgroundGlassHint : text.translucentBackgroundHint,
                          isOn: liquidGlassIsOn ? .constant(true) : $translucentBackground)
                    .disabled(liquidGlassIsOn)
            }
            SettingsCard {
                switchRow("capsule", text.showOutline, isOn: $outlineEnabled)
            }
        }
    }

    private var displaysPage: some View {
        let editor = FeatureStrings.notchEditor(l10n.language)
        return VStack(alignment: .leading, spacing: 20) {
            Text("Automatic shows the island on every enabled display, fitting each screen independently. Click an island to open its controls on that display.")
                .font(.callout).foregroundStyle(.secondary)
            NotchSettingsColumns {
            SettingsCard(title: text.display) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(2, max(1, connectedScreens.count))), alignment: .leading, spacing: 16) {
                ForEach(connectedScreens, id: \.notchPersistentID) { screen in
                    displayCard(screen)
                }
            }
            Text("Display choices are remembered when a monitor reconnects. Configure activity types in \(NotchSettingsTab.activity.title(l10n.language)) and pages in \(NotchSettingsTab.content.title(l10n.language)).")
                .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(title: text.display) {
                Toggle("Show on all displays", isOn: Binding(get: {
                    (NotchDisplay(rawValue: display) ?? .automatic).showsOnAllDisplays
                }, set: { all in
                    preferredDisplay = ""
                    display = (all ? NotchDisplay.automatic : .builtIn).rawValue
                }))
                Text((NotchDisplay(rawValue: display) ?? .automatic).showsOnAllDisplays
                     ? "Every enabled display is included. The interactive island follows the pointer."
                     : "Single-display mode: only the selected display shows the island.")
                    .font(.caption).foregroundStyle(.secondary)
                switchRow("arrow.up.left.and.arrow.down.right", text.hideInFullscreen, isOn: $hideInFullscreen)
                DisclosureGroup("\(text.display) · \(l10n.s.tabAdvanced)") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        // A mode this version no longer offers is treated as automatic, as the island does.
                        choice(text.automatic, symbol: "display.2",
                               selected: (NotchDisplay(rawValue: display) ?? .automatic) == .automatic) { preferredDisplay = ""; display = NotchDisplay.automatic.rawValue }
                        choice(text.builtIn, symbol: "laptopcomputer", selected: display == NotchDisplay.builtIn.rawValue) { preferredDisplay = ""; display = NotchDisplay.builtIn.rawValue }
                        choice(text.mainDisplay, symbol: "display", selected: display == NotchDisplay.main.rawValue && preferredDisplay.isEmpty) { preferredDisplay = ""; display = NotchDisplay.main.rawValue }
                        choice(text.followPointer, symbol: "cursorarrow.motionlines",
                               selected: display == NotchDisplay.pointer.rawValue) { preferredDisplay = ""; display = NotchDisplay.pointer.rawValue }
                        choice(text.allDisplays, symbol: "rectangle.on.rectangle",
                               selected: display == NotchDisplay.all.rawValue) { preferredDisplay = ""; display = NotchDisplay.all.rawValue }
                    }
                }
            }
            if NotchSupport.hasDisplayWithoutNotch {
                SettingsCard(title: text.withoutNotch) {
                    switchRow("eye.slash", "Hide persistent island in full screen",
                              caption: "On by default. In full-screen apps, hide idle content and live activities until you hover the island area. The island stays visible on the desktop. Notifications and volume or brightness feedback can still appear.",
                              isOn: $autoHideWithoutNotch)
                }
            }
            if NotchSupport.hasNotchedDisplay {
                SettingsCard(title: "Displays with a notch") {
                    switchRow("eye.slash", editor.hiddenUntilHover,
                              caption: "Hide the hardware-notch island and all of its automatic feedback until you hover it.",
                              isOn: Binding(get: { hover && hideUntilHover }, set: { hidden in
                                  hideUntilHover = hidden
                                  if hidden { hover = true; hoverExpand = true }
                              }))
                }
            }

            DisclosureGroup("\(text.cameraFit) · \(text.capsuleFit)") {
                VStack(alignment: .leading, spacing: 18) {
                    // Only a display without a camera can float the island.
                    if NotchSupport.hasDisplayWithoutNotch {
                        displayGroupHeader(text.withoutNotch, symbol: "display",
                                           caption: "A floating island can use the menu bar freely and resize for its activity.")
                        SettingsCard(title: text.withoutNotch) {
                            HStack(spacing: 10) {
                                silhouetteChoice(.capsule, title: text.capsuleShape)
                                silhouetteChoice(.notch, title: text.notchShape)
                            }
                        }
                        if NotchSilhouette(rawValue: silhouette) ?? .capsule == .capsule {
                            SettingsCard(title: text.capsuleFit) {
                                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                                    // Even widths keep the capsule centred on whole points.
                                    fitSlider(text.width, card: text.capsuleFit, value: $capsuleFitWidth,
                                              range: NotchCapsuleFit.widthRange, step: 2)
                                    fitSlider(text.height, card: text.capsuleFit, value: $capsuleFitHeight,
                                              range: NotchCapsuleFit.heightRange, step: 1)
                                    fitSlider(text.fromTop, card: text.capsuleFit, value: $capsuleFitDrop,
                                              range: NotchCapsuleFit.dropRange, step: 1)
                                }
                                Text(text.capsuleFitHint).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    // Camera fitting is meaningful only around a physical housing.
                    if NotchSupport.hasNotchedDisplay {
                        displayGroupHeader("Displays with a notch", symbol: "laptopcomputer",
                                           caption: "Compact activity marks and readouts fit beside the camera. Other activities appear as separate side pills; hover a pill to open it in place.")
                        SettingsCard(title: text.cameraFit) {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                                // Whole points keep the island centred on the camera's pixels.
                                fitSlider(text.width, card: text.cameraFit, value: $cameraFitWidth,
                                          range: NotchCameraFit.widthRange, step: 1)
                                fitSlider(text.height, card: text.cameraFit, value: $cameraFitHeight,
                                          range: NotchCameraFit.heightRange, step: 0.5)
                            }
                            Text(text.cameraFitHint).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                }
            }

            }
        }
    }

    private func displayCard(_ screen: NSScreen) -> some View {
        let physical = screen.safeAreaInsets.top > 0
        let preference = NotchDisplayPreference.read(displayPreferences)[screen.notchPersistentID] ?? NotchDisplayPreference()
        let shape = preference.silhouette.flatMap(NotchSilhouette.init(rawValue:))
            ?? NotchSilhouette(rawValue: silhouette) ?? .capsule
        let mode = NotchDisplay(rawValue: display) ?? .automatic
        let included = preference.enabled && (mode.showsOnAllDisplays
            || (mode == .builtIn && CGDisplayIsBuiltin(screen.notchDisplayID) != 0)
            || (mode == .main && (preferredDisplay.isEmpty ? screen == NSScreen.withMenuBar : preferredDisplay == screen.notchPersistentID))
            || mode == .pointer)
        return VStack(alignment: .leading, spacing: 12) {
            NotchDisplayIllustration(physical: physical, silhouette: shape, enabled: included)
                .frame(height: 124)
            HStack {
                Text(screen.localizedName).font(.headline).lineLimit(1)
                Spacer()
                Circle().fill(included ? Color.green : Color.secondary).frame(width: 7, height: 7)
            }
            Text(included ? (mode == .pointer ? "Follows pointer" : "Included") : "Excluded by display settings")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show island", isOn: Binding(get: { preference.enabled }, set: { value in
                displayPreferences = NotchDisplayPreference.updating(displayPreferences, id: screen.notchPersistentID) { $0.enabled = value }
                if value && !mode.showsOnAllDisplays { preferredDisplay = ""; display = NotchDisplay.all.rawValue }
            }))
            Toggle("Live activities", isOn: displayBinding(screen, keyPath: \.liveActivities))
                .disabled(!preference.enabled)
            if physical {
                Label("Physical notch · automatic fit", systemImage: "camera.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(height: 28)
            } else {
                Picker("Shape", selection: Binding(get: { preference.silhouette ?? "" }, set: { value in
                    displayPreferences = NotchDisplayPreference.updating(displayPreferences, id: screen.notchPersistentID) {
                        $0.silhouette = value.isEmpty ? nil : value
                    }
                })) {
                    Text("Default").tag("")
                    Text(text.capsuleShape).tag(NotchSilhouette.capsule.rawValue)
                    Text(text.notchShape).tag(NotchSilhouette.notch.rawValue)
                }.pickerStyle(.menu)
            }
            Button("Use only this display") {
                displayPreferences = NotchDisplayPreference.updating(displayPreferences, id: screen.notchPersistentID) { $0.enabled = true }
                preferredDisplay = screen.notchPersistentID
                display = NotchDisplay.main.rawValue
            }.buttonStyle(.bordered).frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(included ? Color.accentColor.opacity(0.5) : .clear) }
    }

    private func displayBinding(_ screen: NSScreen, keyPath: WritableKeyPath<NotchDisplayPreference, Bool>) -> Binding<Bool> {
        Binding(get: {
            (NotchDisplayPreference.read(displayPreferences)[screen.notchPersistentID] ?? NotchDisplayPreference())[keyPath: keyPath]
        }, set: { value in
            displayPreferences = NotchDisplayPreference.updating(displayPreferences, id: screen.notchPersistentID) { $0[keyPath: keyPath] = value }
        })
    }

    /// Whether the open island draws Liquid Glass, by the island's own rule.
    /// Reduce Transparency keeps it black, so the switch then shows the saved
    /// choice as it does with the glass off.
    private var liquidGlassIsOn: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *) { return liquidGlass && !reduceTransparency }
#endif
        return false
    }

    /// The sections in a list of their own, the chosen one's options beside
    /// it, and the island as it will look. A wide window keeps the preview
    /// in a column that never scrolls away. Narrow windows use a page picker
    /// and collapsible page arrangement and preview, keeping options in view.
    private func contentEditor(in size: CGSize) -> some View {
        let wide = size.width >= 900
        return AnyView(Group {
            if wide {
                HStack(alignment: .top, spacing: 20) {
                    pageLibrary.frame(width: max(290, size.width * 0.32))
                    pageInspector(width: size.width * 0.68 - 20)
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker(editor.sections, selection: $selectedModule) {
                            ForEach(orderedModules) { module in Text(module.title(l10n.language)).tag(module) }
                        }.pickerStyle(.menu)
                        Toggle(selectedModule.title(l10n.language), isOn: selectedModule.isAvailable() ? moduleBinding(selectedModule) : .constant(false))
                            .labelsHidden().toggleStyle(.switch).disabled(!selectedModule.isAvailable())
                    }
                    DisclosureGroup(editor.sections) { pageLibrary.frame(height: min(320, size.height * 0.5)) }
                    pageInspector(width: size.width)
                }
            }
        })
    }

    private var pageLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(editor.findAction, text: $pageQuery).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(orderedModules.filter { pageQuery.isEmpty || $0.title(l10n.language).localizedStandardContains(pageQuery) }) { module in
                        HStack(spacing: 8) {
                            Button { selectedModule = module } label: {
                                HStack(spacing: 10) {
                                    NotchSectionTile(module: module, shown: isShown(module), side: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(module.title(l10n.language)).font(.callout.weight(.semibold))
                                        Text(editor.summary(module)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(NotchSettingsButtonStyle())
                            Toggle(module.title(l10n.language), isOn: module.isAvailable() ? moduleBinding(module) : .constant(false))
                                .labelsHidden().toggleStyle(.checkbox).disabled(!module.isAvailable())
                        }.padding(10)
                            .background(selectedModule == module ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }
                    DisclosureGroup(editor.reorderHint) { sectionList.frame(height: 340) }
                        .padding(.top, 8)
                }
            }
        }
    }

    private func pageInspector(width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NotchSectionHeader(module: selectedModule, shown: isShown(selectedModule),
                    reason: selectedModule.isAvailable() ? nil : moduleFeature(selectedModule).map(enableFeatureReason) ?? text.disabled) {
                    router.request(FeatureSettingsDestination(.features), targetFeature: moduleFeature(selectedModule))
                }
                if selectedModule.isAvailable(), hasOptions(selectedModule) {
                    SettingsCard { moduleOptions(selectedModule) }
                } else if selectedModule.isAvailable() {
                    Text(editor.noOptions).font(.callout).foregroundStyle(.secondary)
                }
                DisclosureGroup(editor.preview) { preview(width: width, limit: 360) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 22)
        }.id(selectedModule)
    }

    private func preview(width: CGFloat, limit: CGFloat) -> some View {
        NotchIslandPreview(module: selectedModule, hidden: !isShown(selectedModule))
            .frame(height: NotchIslandPreview.height(width: width, limit: limit))
    }

    /// Every section in the island's order, each with the switch that shows it.
    private var sectionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editor.sections).font(.headline)
                Text(editor.sectionsHint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(orderedModules) { module in
                            NotchSectionListRow(module: module, included: moduleBinding(module), available: module.isAvailable(),
                                                selected: selectedModule == module,
                                                order: Binding(get: { orderedModules },
                                                               set: { order = $0.map(\.rawValue).joined(separator: ",") }),
                                                dragging: $draggingModule) { selectedModule = module }
                                .id(module)
                        }
                    }
                }
                .scrollIndicators(.automatic)
                // A section chosen from the island itself may sit low in the list.
                .onAppear { reader.scrollTo(selectedModule) }
                .onChange(of: selectedModule) { _, module in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { reader.scrollTo(module) }
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func isShown(_ module: NotchModule) -> Bool {
        module.isAvailable() && moduleBinding(module).wrappedValue
    }

    /// The mixer, the system page and the tools arrange themselves in the island.
    private func hasOptions(_ module: NotchModule) -> Bool {
        ![.mixer, .system, .tools].contains(module)
    }

    @ViewBuilder private func moduleOptions(_ module: NotchModule) -> some View {
        switch module {
        case .controls:
            let primary = [NotchControlItem.music, .volume, .brightness]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 8)], spacing: 8) {
                ForEach(primary) { item in
                    toggleCard(item.title(l10n), symbol: item.symbol, value: controlBinding(item), available: item.isAvailable(),
                               reason: controlReason(item), reservesReason: !primary.allSatisfy { $0.isAvailable() },
                               unavailableAction: controlUnavailableAction(item))
                }
            }
            Text(text.controlShortcuts).font(.subheadline.weight(.medium))
            TextField(editor.findAction, text: $controlQuery).textFieldStyle(.roundedBorder)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 8)], spacing: 8) {
                ForEach(orderedShortcuts.filter { controlQuery.isEmpty || $0.title(l10n).localizedStandardContains(controlQuery) }) { item in
                    PanelReorderableItem(item: item,
                        order: Binding(get: { orderedShortcuts }, set: { controlOrder = $0.map(\.rawValue).joined(separator: ",") }),
                        dragging: $draggingControl) {
                        NotchControlCatalogRow(symbol: item.symbol, title: item.title(l10n), included: controlBinding(item),
                            available: item.isAvailable(), unavailableReason: controlReason(item),
                            unavailableAction: controlUnavailableAction(item))
                    }
                }
            }
        case .music:
            let music = FeatureStrings.notchMusicExtras(l10n.language)
            Button { tab = .activity } label: {
                Label(NotchSettingsTab.activity.title(l10n.language), systemImage: "livephoto")
            }
            DisclosureGroup(l10n.s.tabAdvanced) {
                switchRow("play.rectangle", music.includeOtherPlayers, isOn: $includeOtherPlayers)
            }
            switchRow("text.quote", music.enableLyrics, isOn: $lyricsEnabled)
                .disabled(!AppFeature.notchLyrics.isAvailable)
            if lyricsEnabled, AppFeature.notchLyrics.isAvailable {
                switchRow("globe", music.online, caption: music.onlineHint, isOn: $lyricsOnline)
                    .padding(.leading, settingsRowTextInset)
            }
            switchRow("list.bullet", music.enableQueue, caption: music.queueDescription, isOn: $queueEnabled)
                .disabled(!AppFeature.notchQueue.isAvailable)
            switchRow("waveform", music.liveEqualizer,
                      caption: NotchAudioLevelSupport.isSupported ? music.liveEqualizerHint : music.liveEqualizerUnavailable,
                      isOn: $liveEqualizer)
                .disabled(!NotchAudioLevelSupport.isSupported || !AppFeature.notchLiveEqualizer.isAvailable)
        case .notifications:
            let notifications = FeatureStrings.notchNotifications(l10n.language)
            switchRow("bell.slash", notifications.hideSystemBanner, caption: notifications.hideSystemBannerHint,
                      isOn: $dismissNativeNotifications)
            if notificationsEnabled, !permissions.accessibility { PermissionRow(kind: .accessibility) }
        case .downloads:
            NotchDownloadsSettingsControls()
                .toggleStyle(TrailingSwitchToggleStyle())
        case .calendar:
            let calendar = FeatureStrings.notchCalendar(l10n.language)
            Text(calendar.permission).font(.callout).foregroundStyle(.secondary)
            if permissions.calendarAccess == .fullAccess {
                Label(l10n.s.permissionGranted, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(calendar.allow, action: permissions.requestCalendar).disabled(permissions.requestingCalendar)
                Button(calendar.settings, action: permissions.openCalendarSettings)
            }
            Divider()
            switchRow("calendar.badge.clock", calendar.countdown, caption: calendar.countdownHint,
                      isOn: $calendarCountdown)
            switchRow("hourglass", calendar.timeLeft, caption: calendar.timeLeftHint, isOn: $calendarTimeLeft)
            if permissions.calendarAccess == .fullAccess { NotchCalendarSelection() }
        case .timer:
            switchRow("speaker.wave.2", FeatureStrings.notchActivities(l10n.language).soundEnabled, isOn: $timerSoundEnabled)
                .disabled(!AppFeature.notchTimer.isAvailable)
        case .camera:
            Text(FeatureStrings.notchActivities(l10n.language).cameraHint).font(.callout).foregroundStyle(.secondary)
            if permissions.camera == .granted {
                Label(l10n.s.permissionGranted, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(l10n.s.permissionRequest, action: permissions.requestCamera)
                Button(l10n.s.permissionOpenSettings, action: permissions.openCameraSettings)
            }
        case .files:
            destination(text.files, symbol: "tray.full", value: $shelfWindow, available: AppFeature.shelf.isAvailable)
            if shelfWindow { switchRow("hand.draw", text.dragReveal, isOn: $dragReveal) }
            if AppFeature.mediaTools.isAvailable {
                Text(FeatureStrings.notchFiles(l10n.language).optimizeDropHint)
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .clipboard:
            destination(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboardWindow, available: AppFeature.clipboardHistory.isAvailable)
            switchRow("doc.on.clipboard", text.clipboardActivity, caption: text.privacy, isOn: $clipboard)
        case .captures:
            switchRow("record.circle.fill", "Screen recording live activity",
                      caption: "Show a live recording pill with elapsed timer, pause/resume, and stop controls in Dynamic Island.",
                      isOn: $recordingLiveActivity)
                .disabled(!AppFeature.screenRecorder.isAvailable)
            switchRow("camera.viewfinder", text.captureActivity, isOn: $capture).disabled(!AppFeature.screenshot.isAvailable)
            if capture {
                ScreenshotDefaultActionPicker(strings: FeatureStrings.screenshot(l10n.language), selection: $captureAction)
                    .padding(.leading, settingsRowTextInset)
            }
        case .scratchpad:
            destination(FeatureStrings.scratchpad(l10n.language).pageTitle, symbol: "note.text", value: $scratchpad)
        case .dictation:
            Button(DictationStrings.localized(l10n.language).title) {
                SettingsRouter.shared.request(FeatureSettingsDestination(.dictation))
            }
        case .agents:
            NotchAgentsSettingsControls()
        case .watch:
            NotchWatchSettingsControls()
                .toggleStyle(TrailingSwitchToggleStyle())
        case .teleprompter:
            VStack(alignment: .leading, spacing: 10) {
                Text("Configure scripts, voice tracking, font size, mirror mode, and countdown in the dedicated Teleprompter settings.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Teleprompter Settings") {
                    SettingsRouter.shared.request(FeatureSettingsDestination(.teleprompter))
                }
                .buttonStyle(.borderedProminent)
            }
        case .mixer, .system, .tools:
            EmptyView()
        }
    }

    private var activityPage: some View {
        NotchSettingsColumns {
            SettingsCard(title: editor.activity) {
                switchRow("music.note", text.playingMusic, isOn: $showPlayingMusic)
                switchRow("cup.and.saucer", FeatureStrings.notchActivities(l10n.language).keepAwakeActivity,
                          caption: FeatureStrings.notchActivities(l10n.language).keepAwakeActivityHint, isOn: $keepAwakeActivity)
                    .disabled(!AppFeature.keepAwake.isAvailable)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach([NotchModule.timer, .calendar, .downloads, .agents, .watch, .teleprompter]) { module in
                        Button { showModule(module) } label: {
                            Label(module.title(l10n.language), systemImage: module.symbol)
                                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        }.buttonStyle(.bordered)
                    }
                }
            }
            SettingsCard(title: editor.resting) {
                HStack(spacing: 10) {
                    idleChoice(.none, title: text.idleNone, symbol: "minus")
                    if PowerSampler.hasInternalBattery {
                        idleChoice(.battery, title: text.battery, symbol: "battery.75percent")
                    }
                    idleChoice(.music, title: text.music, symbol: "music.note")
                    // Offered once the section is on; the island would show nothing before.
                    if offersAgentsResting {
                        idleChoice(.agents, title: FeatureStrings.notchAgents(l10n.language).restingTitle, symbol: "sparkles")
                    }
                }
                switchRow("menubar.rectangle", text.coverMenus, caption: text.coverMenusHint, isOn: $coversMenus)
            }
            if NotchSupport.modules().contains(.music) {
                let music = FeatureStrings.notchMusicExtras(l10n.language)
                SettingsCard(title: FeatureStrings.radialMenu(l10n.language).mediaNowPlaying) {
                    if showPlayingMusic {
                        switchRow("eye.slash", music.hideWhenPlayerActive, caption: music.hideWhenPlayerActiveHint, isOn: $hideMusicWhenPlayerActive)
                        pauseTimeoutSlider(music)
                    }
                }
            }
            SettingsCard {
                switchRow("record.circle.fill", "Screen recording live activity",
                          caption: "Prioritized alongside Timer with built-in elapsed clock, pause/resume, and stop controls.",
                          isOn: $recordingLiveActivity)
                    .disabled(!AppFeature.screenRecorder.isAvailable)
                switchRow("square.stack.3d.up.fill", "Shortcuts live activity",
                          caption: "Keep running shortcuts centered, with other activities in side pills.", isOn: $shortcutsEnabled)
            }
            DisclosureGroup(l10n.s.tabAdvanced) {
                SettingsCard {
                    switchRow("phone.fill", "Call live activity",
                              caption: "Paused while macOS provides its persistent call notification. The implementation is retained for future use.", isOn: $callsEnabled)
                        .disabled(!NotchCallSupport.isAvailable)
                }
            }
        }
    }

    private var behaviorPage: some View {
        NotchSettingsColumns {
            SettingsCard(title: editor.opening) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    choice(editor.clickOpen, symbol: "cursorarrow", selected: !hover) { hideUntilHover = false; hover = false }
                    choice(editor.hoverPreview, symbol: "rectangle.topthird.inset.filled", selected: hover && !hoverExpand && !hideUntilHover) { hideUntilHover = false; hover = true; hoverExpand = false }
                    choice(editor.hoverExpand, symbol: "arrow.up.left.and.arrow.down.right", selected: hover && hoverExpand && !hideUntilHover) { hideUntilHover = false; hover = true; hoverExpand = true }
                }
                if hover { hoverDelayControl }
            }
            SettingsCard(title: editor.reopening) {
                SettingsRow(symbol: "arrow.uturn.backward", title: editor.reopening) {
                    Picker(editor.reopening, selection: Binding(get: {
                        guard returnHome else { return "" }
                        return NotchModule(rawValue: homeModule) != nil
                            || NotchReopeningDestination(rawValue: homeModule) != nil
                            ? homeModule : NotchModule.controls.rawValue
                    }, set: { value in
                        returnHome = !value.isEmpty
                        if returnHome { homeModule = value }
                    })) {
                        Text(editor.lastPage).tag("")
                        Text(text.panel).tag(NotchReopeningDestination.appPanel.rawValue)
                        Text(text.sectionsTitle).tag(NotchReopeningDestination.explore.rawValue)
                        ForEach(NotchSupport.modules()) { module in
                            Text(module.title(l10n.language)).tag(module.rawValue)
                        }
                        if let saved = NotchModule(rawValue: homeModule), !NotchSupport.modules().contains(saved) {
                            Text(saved.title(l10n.language)).tag(homeModule).disabled(true)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                switchRow("livephoto", editor.openActivity, caption: editor.openActivityHint, isOn: $opensActivity)
            }

            SettingsCard(title: FeatureStrings.notchGestures(l10n.language).title) {
                switchRow("hand.draw", FeatureStrings.notchGestures(l10n.language).title,
                          caption: gesturesEnabled ? FeatureStrings.notchGestures(l10n.language).hint : nil,
                          isOn: $gesturesEnabled)
                    .disabled(!AppFeature.notchGestures.isAvailable)
                switchRow("waveform.path", text.hapticFeedback, isOn: $hapticFeedback)
            }

        }
    }

    private var notificationsPage: some View {
        NotchSettingsColumns {
            SettingsCard(title: NotchModule.notifications.title(l10n.language)) {
                Toggle(NotchModule.notifications.title(l10n.language), isOn: moduleBinding(.notifications))
                    .disabled(!AppFeature.notchNotifications.isAvailable)
                if !AppFeature.notchNotifications.isAvailable {
                    Button(enableFeatureReason(.notchNotifications)) { showFeature(.notchNotifications) }
                }
                moduleOptions(.notifications)
            }
            SettingsCard(title: editor.feedback) {
                let volumeAvailable = AppFeature.mixer.isAvailable
                let brightnessAvailable = AppFeature.brightness.isAvailable && brightnessControlEnabled
                let keyboardLightAvailable = AppFeature.brightness.isAvailable && BrightnessService.keyboardLightIsSupported
                let microphoneAvailable = AppFeature.micMute.isAvailable
                // A Mac without a battery has no battery notices, so that card
                // is left out rather than shown waiting for Power.
                let hasBattery = PowerSampler.hasInternalBattery
                let batteryAvailable = AppFeature.monitorPower.isAvailable
                let accessoriesAvailable = AppFeature.notchAccessories.isAvailable && AppFeature.monitorPower.isAvailable
                let clipboardAvailable = AppFeature.clipboardHistory.isAvailable && clipboardHistoryEnabled
                    && NotchSupport.modules().contains(.clipboard)
                let capturesAvailable = AppFeature.screenshot.isAvailable && NotchSupport.modules().contains(.captures)
                let musicAvailable = NotchSupport.modules().contains(.music)
                let reserves = ![volumeAvailable, brightnessAvailable, keyboardLightAvailable, microphoneAvailable,
                                 batteryAvailable || !hasBattery, accessoriesAvailable, clipboardAvailable, capturesAvailable,
                                 musicAvailable].allSatisfy { $0 }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
                    toggleCard(text.volume, symbol: "speaker.wave.2", value: $volume, available: volumeAvailable,
                               reason: enableFeatureReason(.mixer), reservesReason: reserves,
                               unavailableAction: { showFeature(.mixer) })
                    toggleCard(text.brightness, symbol: "sun.max", value: $brightness, available: brightnessAvailable,
                               reason: AppFeature.brightness.isAvailable ? editor.enableSetting(FeatureStrings.brightness(l10n.language).enable) : enableFeatureReason(.brightness),
                               reservesReason: reserves,
                               unavailableAction: {
                                   if AppFeature.brightness.isAvailable {
                                       router.request(AppFeature.brightness.settingsDestination)
                                   } else {
                                       showFeature(.brightness)
                                   }
                               })
                    toggleCard(FeatureStrings.brightness(l10n.language).keyboardLight, symbol: "light.max", value: $keyboardLight,
                              available: keyboardLightAvailable,
                              reason: !AppFeature.brightness.isAvailable ? enableFeatureReason(.brightness) : editor.keyboardLightUnavailable,
                              reservesReason: reserves,
                              unavailableAction: !AppFeature.brightness.isAvailable ? { showFeature(.brightness) } : nil)
                    toggleCard(l10n.s.mixerInputTitle, symbol: "mic", value: $microphone, available: microphoneAvailable,
                               reason: enableFeatureReason(.micMute), reservesReason: reserves,
                               unavailableAction: { showFeature(.micMute) })
                    if hasBattery {
                        toggleCard(text.battery, symbol: "battery.75percent", value: $battery, available: batteryAvailable,
                                   reason: enableFeatureReason(.monitorPower), reservesReason: reserves,
                                   unavailableAction: { showFeature(.monitorPower) })
                    }
                    toggleCard(FeatureStrings.notchActivities(l10n.language).accessories, symbol: "headphones", value: $accessoriesEnabled,
                              available: accessoriesAvailable,
                              reason: enableFeatureReason(AppFeature.monitorPower.isAvailable ? .notchAccessories : .monitorPower),
                              reservesReason: reserves,
                              unavailableAction: {
                                  showFeature(AppFeature.monitorPower.isAvailable ? .notchAccessories : .monitorPower)
                              })
                    toggleCard(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboard,
                               available: clipboardAvailable, reason: clipboardFeedbackReason, reservesReason: reserves,
                               unavailableAction: { openClipboardFeedbackSetup() })
                    toggleCard(text.captures, symbol: "camera.viewfinder", value: $capture, available: capturesAvailable,
                               reason: AppFeature.screenshot.isAvailable ? editor.showPage(text.captures) : enableFeatureReason(.screenshot),
                               reservesReason: reserves,
                               unavailableAction: {
                                   if AppFeature.screenshot.isAvailable { showModule(.captures) }
                                   else { showFeature(.screenshot) }
                               })
                    toggleCard(text.newTrack, symbol: "music.note", value: $trackChange, available: musicAvailable,
                               reason: editor.showPage(text.music), reservesReason: reserves,
                               unavailableAction: { showModule(.music) })
                }
                if accessoriesEnabled { Text(FeatureStrings.notchActivities(l10n.language).accessoryDescription).font(.caption).foregroundStyle(.secondary) }
                if enabled, (volume || brightness || keyboardLight), !permissions.accessibility { PermissionRow(kind: .accessibility) }
            }
            SettingsCard(title: "Focus") {
                switchRow("moon.fill", "Focus On / Off pill",
                          caption: "Show an iOS-style Focus status notification in Dynamic Island whenever Focus turns on or off.",
                          isOn: $focusEnabled)
                if focusEnabled {
                    switchRow("bell.slash.fill", "Hide macOS Focus banner",
                              caption: "Take over the native macOS Focus notification at the system level so only Dynamic Island appears.",
                              isOn: $focusHideNative)
                    if focusHideNative, !permissions.accessibility {
                        PermissionRow(kind: .accessibility)
                    }
                }
            }
        }
    }

    private var routingPage: some View {
        NotchSettingsColumns {
            SettingsCard(title: text.panel) {
                destination(text.panel, symbol: "bubble.middle.top", value: $appPanel)
                Text(editor.appPanelHint).font(.caption).foregroundStyle(.secondary)
                switchRow("menubar.rectangle", editor.hideMenuBarIcon, caption: editor.hideMenuBarIconHint,
                          isOn: $hidesMenuBarIcon)
            }
            SettingsCard(title: editor.destinations) {
                destination(text.tools, symbol: "square.grid.2x2", value: $quickPanel, available: AppFeature.quickLauncher.isAvailable)
                destination(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboardWindow, available: AppFeature.clipboardHistory.isAvailable)
                destination(text.files, symbol: "tray.full", value: $shelfWindow, available: AppFeature.shelf.isAvailable)
                destination(text.captures, symbol: "camera.viewfinder", value: $captureControls)
                destination(FeatureStrings.scratchpad(l10n.language).pageTitle, symbol: "note.text", value: $scratchpad, available: AppFeature.scratchpad.isAvailable)
            }
        }
    }

    private var privacyPage: some View {
        NotchSettingsColumns {
            SettingsCard(title: editor.privacy) {
                switchRow("camera.viewfinder", text.showInCaptures, isOn: $showInCaptures)
            }
            let locked = FeatureStrings.notchLockScreen(l10n.language)
            SettingsCard(title: locked.title) {
                switchRow("lock.display", locked.show, caption: locked.showHint, isOn: $lockScreen)
                switchRow("speaker.wave.2", locked.sounds, caption: locked.soundsHint, isOn: $lockSounds)
            }        }
    }

    private var hoverDelayControl: some View {
        let value = Binding(get: { NotchSupport.sanitizedHoverDelay(hoverDelay) },
                            set: { hoverDelay = NotchSupport.sanitizedHoverDelay($0) })
        let formatted = String(format: editor.activationTimeFormat, locale: Locale(identifier: l10n.language.rawValue), value.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(editor.activationTime)
                Spacer()
                Text(formatted).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: NotchSupport.hoverDelayRange, step: 0.05) {
                Text(editor.activationTime)
            }.labelsHidden().accessibilityValue(formatted)
            Text(editor.activationTimeHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func displayGroupHeader(_ title: String, symbol: String, caption: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(caption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }

    private func choice(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 68).padding(8)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1) }
        }.buttonStyle(NotchSettingsButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Each outline in a slice of menu bar, drawn as the island draws it.
    private func silhouetteChoice(_ item: NotchSilhouette, title: String) -> some View {
        let selected = (NotchSilhouette(rawValue: silhouette) ?? .capsule) == item
        return Button { silhouette = item.rawValue } label: {
            VStack(spacing: 10) {
                NotchSilhouetteSample(silhouette: item)
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 68).padding(8)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1) }
        }.buttonStyle(NotchSettingsButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func enableFeatureReason(_ feature: AppFeature) -> String {
        editor.enableFeature(feature.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language)))
    }

    private func showFeature(_ feature: AppFeature) {
        router.request(FeatureSettingsDestination(.features), targetFeature: feature)
    }

    private func showModule(_ module: NotchModule) {
        selectedModule = module
        settingsQuery = ""
        tab = .content
    }

    /// A control that opens a page is off while that page is hidden, or while
    /// the feature behind it is disabled; the others follow their feature.
    private func controlReason(_ item: NotchControlItem) -> String {
        switch item.setupRequirement {
        case .feature(let feature): return enableFeatureReason(feature)
        case .page(let module, let feature): return pageReason(module, feature: feature)
        case .none: return text.disabled
        }
    }

    private func controlUnavailableAction(_ item: NotchControlItem) -> (() -> Void)? {
        switch item.setupRequirement {
        case .feature(let feature):
            return { showFeature(feature) }
        case .page(let module, let feature):
            return {
                if let feature, !feature.isAvailable { showFeature(feature) }
                else { showModule(module) }
            }
        case .none: return nil
        }
    }

    private func moduleFeature(_ module: NotchModule) -> AppFeature? {
        module.setupFeature()
    }

    private func pageReason(_ module: NotchModule, feature: AppFeature?) -> String {
        if let feature, !feature.isAvailable { return enableFeatureReason(feature) }
        return editor.showPage(module.title(l10n.language))
    }

    private var clipboardFeedbackReason: String {
        let title = FeatureStrings.clipboard(l10n.language).title
        if !AppFeature.clipboardHistory.isAvailable { return enableFeatureReason(.clipboardHistory) }
        if !clipboardHistoryEnabled { return editor.enableSetting(FeatureStrings.clipboard(l10n.language).enable) }
        return editor.showPage(title)
    }

    private func openClipboardFeedbackSetup() {
        if !AppFeature.clipboardHistory.isAvailable { showFeature(.clipboardHistory) }
        else if !clipboardHistoryEnabled { router.request(AppFeature.clipboardHistory.settingsDestination) }
        else { showModule(.clipboard) }
    }

    private func toggleCard(_ title: String, symbol: String, value: Binding<Bool>, available: Bool, reason: String? = nil,
                            reservesReason: Bool = false, unavailableAction: (() -> Void)? = nil) -> some View {
        NotchControlCatalogRow(symbol: symbol, title: title, included: value, available: available,
                              unavailableReason: available ? nil : reason ?? text.disabled,
                              unavailableAction: unavailableAction)
    }

    private var offersAgentsResting: Bool { agentsEnabled && NotchAgentSupport.isEnabled() }

    /// What the closed island rests with. A saved AI reading waits, unchanged,
    /// while its section is off, and the island rests empty meanwhile. So does
    /// a saved battery reading on a Mac without a battery.
    private var restingChoice: NotchIdleContent {
        let choice: NotchIdleContent = NotchIdleContent(rawValue: idle) ?? .none
        if choice == .battery, !PowerSampler.hasInternalBattery { return .none }
        return choice == .agents && !offersAgentsResting ? .none : choice
    }

    private func idleChoice(_ item: NotchIdleContent, title: String, symbol: String) -> some View {
        Button { idle = item.rawValue } label: {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    if item != .none {
                        Image(systemName: symbol).font(.system(size: 11))
                        RoundedRectangle(cornerRadius: 4).fill(.black).frame(width: 20, height: 12)
                        if item == .battery || item == .agents { Text(item == .agents ? "62%" : "76%").font(.system(size: 9, weight: .medium)) }
                        else { Image(systemName: item == .music ? "waveform" : "minus").font(.system(size: 9)) }
                    } else { Color.clear.frame(width: 50, height: 12) }
                }.foregroundStyle(.white).padding(10).background(.black, in: Capsule())
                Text(title).font(.system(size: 11, weight: .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(restingChoice == item ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(NotchSettingsButtonStyle()).accessibilityAddTraits(restingChoice == item ? .isSelected : [])
    }

    private func destination(_ title: String, symbol: String, value: Binding<Bool>, available: Bool = true) -> some View {
        SettingsChoiceRow(symbol: symbol, title: title, selection: value) {
            Text(text.title).tag(true)
            Text(editor.separate).tag(false)
        }.disabled(!available)
    }

    /// An option with its icon, one line and a switch, like every other page.
    private func switchRow(_ symbol: String, _ title: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    private var expandedSizeSlider: some View {
        let strings = FeatureStrings.notchExpandedSize(l10n.language)
        let bounded = Binding(get: { NotchSize.expandedScale(expandedScale) },
                              set: { expandedScale = NotchSize.expandedScale($0) })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label(strings.title, systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                Text(bounded.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().foregroundStyle(.secondary)
                    .frame(minWidth: 42, alignment: .trailing)
                Button {
                    expandedScale = NotchSize.defaultExpandedScale
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help(l10n.s.shortcutReset)
                .accessibilityLabel(l10n.s.shortcutReset + ", " + strings.title)
                .disabled(abs(bounded.wrappedValue - NotchSize.defaultExpandedScale) < 0.001)
            }
            Slider(value: bounded, in: NotchSize.expandedScaleRange, step: 0.05) {
                Text(strings.title)
            }.labelsHidden()
                .accessibilityValue(bounded.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
            Text(strings.hint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dimensionSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, fallback: Double) -> some View {
        let bounded = Binding(get: { NotchSize.clamped(value.wrappedValue, to: range, fallback: fallback) },
                              set: { value.wrappedValue = NotchSize.clamped($0, to: range, fallback: fallback) })
        return GridRow {
            // The slider carries the name for VoiceOver.
            Text(title).fixedSize().accessibilityHidden(true)
            Slider(value: bounded, in: range, step: 10) { Text(title) }.labelsHidden()
            Text(Int(bounded.wrappedValue), format: .number)
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 38)
        }
    }

    /// A correction around zero, signed so the untouched value reads as none.
    private func fitSlider(_ title: String, card: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double) -> some View {
        let bounded = Binding(get: { NotchSize.clamped(value.wrappedValue, to: range, fallback: 0) },
                              set: { value.wrappedValue = NotchSize.clamped($0, to: range, fallback: 0) })
        let formatted = bounded.wrappedValue.formatted(.number.sign(strategy: .always(includingZero: false))
            .precision(.fractionLength(0...1)).locale(Locale(identifier: l10n.language.rawValue)))
        return GridRow {
            Text(title).fixedSize().accessibilityHidden(true)
            // Other cards have sliders with the same names.
            Slider(value: bounded, in: range, step: step) { Text("\(card), \(title)") }.labelsHidden()
                .accessibilityValue(formatted)
            Text(formatted).monospacedDigit().foregroundStyle(.secondary).frame(width: 38)
        }
    }
    private var orderedShortcuts: [NotchControlItem] {
        let stored = controlOrder.split(separator: ",").compactMap { NotchControlItem(rawValue: String($0)) }
        var seen = Set<NotchControlItem>()
        return (stored + NotchControlItem.allCases).filter {
            $0 != .volume && $0 != .brightness && $0 != .music && seen.insert($0).inserted
        }
    }

    private func controlBinding(_ item: NotchControlItem) -> Binding<Bool> {
        Binding {
            !hiddenControls.split(separator: ",").contains(Substring(item.rawValue))
        } set: { shown in
            var values = Set(hiddenControls.split(separator: ",").map(String.init))
            if shown {
                values.remove(item.rawValue)
                var ordered = controlOrder.split(separator: ",").map(String.init)
                if !ordered.contains(item.rawValue) { ordered.append(item.rawValue); controlOrder = ordered.joined(separator: ",") }
            } else { values.insert(item.rawValue) }
            hiddenControls = values.sorted().joined(separator: ",")
        }
    }

    private func moduleBinding(_ module: NotchModule) -> Binding<Bool> {
        Binding {
            (module != .timer || timerEnabled) && (module != .camera || cameraEnabled)
                && (module != .calendar || calendarEnabled) && (module != .notifications || notificationsEnabled)
                && (module != .agents || agentsEnabled) && (module != .watch || watchEnabled)
                && (module != .teleprompter || teleprompterEnabled)
                && !hidden.split(separator: ",").contains(Substring(module.rawValue))
        } set: { shown in
            if module == .timer { timerEnabled = shown }
            if module == .camera { cameraEnabled = shown }
            if module == .calendar { calendarEnabled = shown }
            if module == .notifications { notificationsEnabled = shown }
            if module == .agents { agentsEnabled = shown }
            if module == .watch { watchEnabled = shown }
            if module == .teleprompter { teleprompterEnabled = shown }
            var values = Set(hidden.split(separator: ",").map(String.init))
            if shown { values.remove(module.rawValue) } else { values.insert(module.rawValue) }
            hidden = values.sorted().joined(separator: ",")
        }
    }

    private func pauseTimeoutSlider(_ music: NotchMusicExtrasStrings) -> some View {
        let value = Binding(get: { NotchSupport.sanitizedPauseTimeout(musicPauseTimeout) },
                            set: { musicPauseTimeout = NotchSupport.sanitizedPauseTimeout($0) })
        let seconds = Int(value.wrappedValue.rounded())
        let formatted = seconds == 0 ? music.pauseTimeoutOff : String(format: music.pauseTimeoutFormat, locale: Locale(identifier: l10n.language.rawValue), seconds)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(music.pauseTimeout, systemImage: "timer")
                Spacer()
                Text(formatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: NotchSupport.pauseTimeoutRange, step: 1) {
                Text(music.pauseTimeout)
            }
            .labelsHidden()
            .accessibilityLabel(music.pauseTimeout)
            .accessibilityValue(formatted)
            Text(music.pauseTimeoutHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

}

extension NotchControlItem: PanelOrderItem {}

/// A standard menu bar on a display without a camera, at half size, with
/// the resting island in it.
private struct NotchSilhouetteSample: View {
    let silhouette: NotchSilhouette

    var body: some View {
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0,
                                     cameraWidth: 0, menuBarHeight: 24, silhouette: silhouette)
        let island = geometry.restingSize(showsContent: false)
        ZStack(alignment: .top) {
            Rectangle().fill(.primary.opacity(0.08)).frame(height: geometry.menuBarHeight)
            // Menus on the left and status items on the right, clear of the island.
            HStack(spacing: 9) {
                ForEach([26, 36, 30], id: \.self) { width in
                    Capsule().fill(.primary.opacity(0.22)).frame(width: CGFloat(width), height: 8)
                }
                Spacer(minLength: 0)
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.primary.opacity(0.22)).frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: geometry.menuBarHeight)
            NotchShape.island(height: island.height, geometry: geometry).fill(.black)
                .frame(width: island.width, height: island.height)
        }
        .frame(width: 400, height: 48, alignment: .top)
        .background(.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(0.5)
        .frame(width: 200, height: 24)
        .accessibilityHidden(true)
    }
}
