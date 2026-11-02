// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var launcher = QuickLauncherService.shared
    @ObservedObject private var updates = UpdateService.shared
    @AppStorage(DefaultsKey.notchLiquidGlassEnabled) private var glass = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var headerHovered = false
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }

    var body: some View {
        surface
            .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            .foregroundStyle(.white)
            // The window server leaves Liquid Glass out of its hit test, so a
            // click or a wheel over empty glass would reach the window behind:
            // the page stops scrolling between cards and the island loses
            // focus. A fill too faint to see keeps the surface in this window,
            // as the black backdrop does.
            .background(shape.fill(Color.black.opacity(service.usesPillActivityDeck ? 0 : 0.01)))
            .contentShape(shape)
            // The backdrop is a separate, non-interactive hosting view. Claim
            // empty space here so clicks and wheel events stay in this window.
            .onTapGesture { }
            .onChange(of: reduceTransparency) {
                DispatchQueue.main.async { service.refreshPresentation(animated: false) }
            }
            .onChange(of: contrast) {
                DispatchQueue.main.async { service.refreshPresentation(animated: false) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The native stage reserves the envelope once. Only individual
            // card viewports animate, never the whole hosting surface.
            .transaction { if service.usesPillActivityDeck { $0.animation = nil } }
            .environment(\.colorScheme, .dark)
            .environment(\.notchPresentation, true)
            .environment(\.notchGlassSurface, usesGlassSurface)
            .tint(.white)
            .accessibilityIdentifier("notch.surface")
    }

    private var usesGlassSurface: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *), glass, !reduceTransparency {
            // Resting wings, compact activities and small status notices keep
            // blending into the physical camera cutout.
            return service.usesGlassSurface
        }
#endif
        return false
    }

    private var shape: NotchShape {
        NotchShape.island(height: service.surfaceSize.height, geometry: service.geometry)
    }

    @ViewBuilder private var surface: some View {
        if service.showsDictation {
            NotchDictationView(topInset: service.geometry.safeContentTop)
        } else if service.fullscreenCompact {
            Color.clear.accessibilityHidden(true)
        } else if let options = service.captureControls {
            if service.captureControlsCollapsed, floats {
                NotchCapsuleCaptureStrip(symbol: options.selectedTool.systemImageName, geometry: service.geometry,
                                         size: service.surfaceSize)
            } else if service.captureControlsCollapsed {
                HStack(spacing: 0) {
                    Image(systemName: options.selectedTool.systemImageName).frame(width: 28)
                    Color.clear.frame(width: service.geometry.cameraWidth)
                    Image(systemName: "chevron.down").frame(width: 28)
                }
                .font(.system(size: 10, weight: .semibold))
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            } else {
                NotchCaptureControlsView(options: options, service: service, layout: service.captureControlsLayout)
            }
        } else if service.expanded && !service.usesPillActivityDeck {
            if service.showingCall {
                NotchCallPanel(service: service).padding(.top, service.geometry.safeContentTop)
            } else { expanded }
        } else if service.dragPlaceholder {
            Label(text.dropHint, systemImage: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.24),
                                      style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, NotchLayout.horizontalInset)
                .padding(.top, service.geometry.safeContentTop)
        } else if service.usesPillActivityDeck {
            activityDeckSurface
                // Physical fullscreen keeps the camera cutout. Fade only
                // the activity content, without animating the deck envelope.
                .transition(.opacity.animation(reduceMotion ? nil
                    : .easeOut(duration: NotchQuickAccessLayout.withdrawalDuration)))
        } else if let notice = service.notice ?? (service.peeking ? nil : service.departingNotice) {
            if service.noticeExpanded, let content = notice.notification {
                NotchNotificationPreviewView(notice: notice, content: content, service: service)
                    .padding(.horizontal, NotchLayout.horizontalInset)
                    .padding(.top, service.geometry.safeContentTop)
                    .padding(.bottom, NotchLayout.bottomInset)
                    .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            } else {
                Button {
                    service.activateNotice(notice)
                } label: {
                    Group {
                        if floats {
                            // A departing notice keeps its own row while the capsule closes.
                            NotchCapsuleNoticeView(notice: notice, geometry: service.geometry,
                                                   size: service.notice == nil ? service.capsuleNoticeSurface(notice)
                                                       : service.surfaceSize)
                        } else {
                            NotchNoticeView(notice: notice, geometry: service.geometry)
                        }
                    }
                    .contentShape(Rectangle())
                }
                // A floating capsule lights up under the pointer. Beside a
                // camera the wash would outline the housing, so the notch keeps
                // its notices plain, as its other strips are.
                .buttonStyle(NotchButtonStyle(cornerRadius: 14, lifts: false, highlights: floats))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(notice.accessibilityText)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { service.activateNotice(notice) }
                .accessibilityHint(text.open)
                .transition(.opacity)
            }
        } else if service.peeking {
            HStack {
                navigation
                Spacer(minLength: 8)
                NotchIconButton(symbol: "chevron.down", title: text.open) { service.open() }
            }
            .padding(.horizontal, NotchLayout.horizontalInset).padding(.top, service.geometry.safeContentTop)
        } else if let activity = service.compactActivity {
            if service.usesPillActivityDeck {
                pillActivityDeck(primary: activity)
            } else if service.showsCompactActivityPicker {
                let layout = service.compactActivityPickerLayout
                VStack(spacing: 0) {
                    let strip = service.compactStripSize(for: activity, companion: service.compactCompanion)
                    ZStack(alignment: .top) {
                        activityStrip(activity, size: strip)
                            .frame(width: strip.width, height: layout.headerHeight, alignment: .top)
                            .id(NotchPickedStrip(activity: activity, companion: service.compactCompanion))
                            .transition(.blurReplace)
                    }
                    .frame(height: layout.headerHeight, alignment: .top)
                    NotchActivityPicker(activities: service.compactActivities, selected: activity,
                                        combinations: service.compactActivityCombinations,
                                        combination: service.compactCompanion.map {
                                            NotchActivityCombination(primary: activity, companion: $0)
                                        },
                                        columns: layout.columns, language: l10n.language,
                                        select: service.selectCompactActivity, combine: service.selectCompactCombination)
                        .padding(.horizontal, NotchActivityPickerLayout.horizontalInset)
                        .padding(.vertical, NotchActivityPickerLayout.verticalInset)
                }
            } else {
                // Hover grows the capsule around its strip, as it grows the
                // notch around its wings. Drawn at the grown size, a song's
                // cover and bars jumped out at once while the shape still grew.
                activityStrip(activity, size: service.compactStripSize(for: activity, companion: service.compactCompanion))
            }
        } else if let departingMusic = service.departingMusic {
            Group {
                if floats { NotchCapsuleMusicStrip(service: service, snapshot: departingMusic) }
                else { NotchMusicStrip(service: service, snapshot: departingMusic) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if floats {
            NotchCapsuleRestingView(service: service, size: service.surfaceSize)
                .transition(.opacity)
        } else {
            compact
                .transition(.opacity)
        }
    }

    /// The island floats as a capsule, whose strips run end to end.
    private var floats: Bool { service.geometry.floats }

    /// Keep one compact rendering tree as activities start and finish.
    /// Individual capsules change without rebuilding the entire deck.
    private var activityDeckSurface: some View {
        ZStack(alignment: .top) {
            if let activity = service.pillDeckPrimaryActivity {
                pillActivityDeck(primary: activity)
                    .transition(.opacity)
            } else if let notice = service.notice {
                Button { service.activateNotice(notice) } label: {
                    Group {
                        if !service.geometry.isNotched { NotchCapsuleNoticeView(notice: notice, geometry: service.geometry, size: service.surfaceSize) }
                        else { NotchNoticeView(notice: notice, geometry: service.geometry, size: service.surfaceSize) }
                    }.background(shape.fill(.black))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Group {
                    if floats { NotchCapsuleRestingView(service: service, size: service.surfaceSize) }
                    else { NotchRestingStrip(service: service).frame(width: service.surfaceSize.width, height: service.surfaceSize.height) }
                }.background(shape.fill(.black)).transition(.opacity)
            }
        }
    }

    /// The primary activity stays centred while the smaller pills balance on
    /// either side. Their transparent gaps are supplied by the native host,
    /// so this remains one coordinated, fluidly resizing island window.
    private func pillActivityDeck(primary: NotchCompactActivity) -> some View {
        let layout = NotchActivityDeckPresentation(primary: primary, primarySize: service.pillSize(for: primary),
            left: service.leftPillActivities.map { ($0, service.pillSize(for: $0)) },
            right: service.rightPillActivities.map { ($0, service.pillSize(for: $0)) })
        return ZStack(alignment: .top) {
            ForEach(layout.items) { item in
                pill(item.activity, size: item.size, x: item.x)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        .transaction { $0.animation = nil }
    }

    private func pill(_ activity: NotchCompactActivity, size: CGSize, x: CGFloat) -> some View {
        let focused = activity == service.pillDeckPrimaryActivity
        let widened = service.widenedPillActivities.contains(activity)
        // The viewport keeps its identity through open and close. Swapping a
        // Button for its label here destroys the moving frame halfway through
        // the transition and makes the card jump to its destination size.
        return pillContent(activity, size: size, x: x, focused: focused, widened: widened)
        .onTapGesture {
            guard !service.expanded, !(focused && service.noticeExpanded) else { return }
            if focused, let notice = service.notice { service.activateNotice(notice) }
            else { service.activatePillActivity(activity) }
        }
        .transition(.opacity.animation(reduceMotion ? nil : .easeOut(duration: NotchQuickAccessLayout.withdrawalDuration)))
        .onHover { service.hoverPillActivity(activity, entered: $0) }
        .onContinuousHover { phase in
            if case .active = phase { service.hoverPillActivity(activity, entered: true) }
        }
        .contextMenu {
            if !focused {
                Button("Make Primary") { service.selectCompactActivity(activity) }
                Button(widened ? "Use Compact Pill" : "Use Wider Pill") { service.togglePillWidth(activity) }
                Divider()
                Button("Move to Left Side") { service.movePillActivity(activity, to: .left) }
                Button("Move to Right Side") { service.movePillActivity(activity, to: .right) }
            }
            Button("Open \(activity.title(l10n.language))") { service.activatePillActivity(activity) }
            Divider()
            Button("Use Automatic Priority") { service.useAutomaticPillPriority() }
        }
        .help(activity.title(l10n.language))
        .accessibilityLabel(activity.title(l10n.language))
        .accessibilityHint("Hover or click to open; right-click to change layout")
        .accessibilityAction { service.activatePillActivity(activity) }
    }

    private func pillContent(_ activity: NotchCompactActivity, size: CGSize, x: CGFloat, focused: Bool, widened: Bool) -> some View {
        ZStack(alignment: .top) {
            if service.expanded && activity == service.expandedPillActivity {
                if service.showingCall { NotchCallPanel(service: service) }
                else { expanded }
            } else if focused, service.noticeExpanded, let notice = service.notice, let content = notice.notification {
                NotchNotificationPreviewView(notice: notice, content: content, service: service)
                    .padding(.horizontal, NotchLayout.horizontalInset)
                    .padding(.top, service.geometry.safeContentTop)
                    .padding(.bottom, NotchLayout.bottomInset)
            } else if focused, let notice = service.notice {
                Group {
                    if !service.geometry.isNotched { NotchCapsuleNoticeView(notice: notice, geometry: service.geometry, size: size) }
                    else { NotchNoticeView(notice: notice, geometry: service.geometry, size: size) }
                }.id(notice.event).transition(.opacity)
            } else if focused && service.geometry.isNotched {
                physicalActivityStrip(activity)
                    .allowsHitTesting(false)
            } else if focused || widened {
                activityStrip(activity, size: size)
            } else {
                NotchPillCompactMark(activity: activity, geometry: service.activitySatelliteGeometry,
                                     physicalSide: service.geometry.isNotched,
                                     onReadingShapeChange: { service.refreshPresentation() })
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28),
                   value: service.expanded && activity == service.expandedPillActivity)
        .modifier(NotchActivityViewport(size: size, x: x,
            geometry: focused ? service.geometry : service.activitySatelliteGeometry, focused: focused))
    }

    /// Reuse the camera-fitted strips, including their measured insets and
    /// original compact marks, instead of adapting a simulated title row.
    @ViewBuilder private func physicalActivityStrip(_ activity: NotchCompactActivity) -> some View {
        let geometry = service.compactGeometry(for: activity)
        switch activity {
        case .music: NotchMusicStrip(service: service, displayGeometry: geometry)
        case .agents: NotchAgentStrip(service: service, displayGeometry: geometry)
        case .timer: NotchTimerStrip(service: service, displayGeometry: geometry)
        case .downloads: NotchDownloadStrip(service: service, displayGeometry: geometry)
        case .calendar: NotchCalendarStrip(service: service, displayGeometry: geometry)
        case .watch: NotchWatchStrip(service: service, displayGeometry: geometry)
        case .keepAwake: NotchKeepAwakeStrip(service: service, displayGeometry: geometry)
        case .call: NotchCallStrip(geometry: geometry, size: geometry.compactActivitySize)
        }
    }

    /// `size` is the capsule's; a hanging strip keeps the camera's geometry.
    @ViewBuilder private func activityStrip(_ activity: NotchCompactActivity, size: CGSize) -> some View {
        if floats || service.usesPillActivityDeck {
            switch activity {
            case .call: NotchCallStrip(geometry: service.activitySatelliteGeometry, size: size)
            case .timer: NotchCapsuleTimerStrip(service: service, size: size, displayGeometry: service.activitySatelliteGeometry)
            case .watch: NotchCapsuleWatchStrip(service: service, size: size, displayGeometry: service.activitySatelliteGeometry)
            case .downloads: NotchCapsuleDownloadStrip(service: service, size: size, displayGeometry: service.activitySatelliteGeometry)
            case .agents: NotchCapsuleAgentStrip(service: service, size: size, displayGeometry: service.activitySatelliteGeometry)
            case .calendar: NotchCapsuleCalendarStrip(service: service, size: size, displayGeometry: service.activitySatelliteGeometry)
            case .music: NotchCapsuleMusicStrip(service: service, size: size, displayGeometry: service.activitySatelliteGeometry)
            case .keepAwake: NotchCapsuleKeepAwakeStrip(service: service, size: size, displayGeometry: service.activitySatelliteGeometry)
            }
        } else {
            switch activity {
            case .call: NotchCallStrip(geometry: service.compactActivityGeometry, size: size)
            case .timer: NotchTimerStrip(service: service)
            case .watch: NotchWatchStrip(service: service)
            case .downloads: NotchDownloadStrip(service: service)
            case .agents: NotchAgentStrip(service: service)
            case .calendar: NotchCalendarStrip(service: service)
            case .music: NotchMusicStrip(service: service)
            case .keepAwake: NotchKeepAwakeStrip(service: service)
            }
        }
    }

    private var compact: some View { NotchRestingStrip(service: service) }

    private var showsDetail: Bool { service.showingAppPanel || service.selectedMetric != nil }

    private var expanded: some View {
        VStack(spacing: NotchLayout.spacing) {
            header.zIndex(1)
            Group {
                if service.showingSections {
                    NotchSectionsView(service: service)
                } else if scrollsVertically {
                    ScrollView {
                        content
                            .frame(height: contentOverflows ? pageSize.height : nil)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.bottom, 4)
                            .contentShape(Rectangle())
                    }
                    .scrollIndicators(.automatic)
                    .notchScrollEdgeFade()
                } else {
                    content
                }
            }
            .frame(width: service.expandedViewContentSize.width, height: service.expandedViewContentSize.height, alignment: .top)
            .clipShape(NotchPageClip(top: service.expandedViewGeometry.headerTopInset
                                        + service.expandedViewGeometry.headerRowHeight + NotchLayout.spacing))
        }
        .padding(.horizontal, NotchLayout.horizontalInset)
        .padding(.top, service.expandedViewGeometry.headerTopInset)
        .padding(.bottom, NotchLayout.bottomInset)
        .frame(width: service.expandedViewSize.width, height: service.expandedViewSize.height, alignment: .top)
    }

    /// Keep each page's minimum usable layout reachable when a custom height
    /// or the display leaves less room. The outer silhouette stays unchanged.
    private var pageSize: CGSize {
        var size = service.expandedViewContentSize
        guard !showsDetail else { return size }
        switch service.selected {
        case .controls:
            let items = NotchSupport.controls()
            let shortcuts = items.filter { $0 != .music && $0 != .volume && $0 != .brightness }
            let scale = service.geometry.expandedScale
            size.height = max(size.height, NotchLayout.controls(
                hasCards: items.contains(.music) || items.contains(.volume) || items.contains(.brightness),
                shortcutCount: shortcuts.count, width: size.width / scale, height: size.height / scale,
                hasMediaTabs: items.contains(.music) && music.sources.count > 1,
                hasPlaybackTimeline: items.contains(.music) && music.hasPlaybackTimeline).height * scale)
        case .timer:
            let session = NotchTimerService.shared.session
            size.height = max(size.height, NotchLayout.timer(
                mode: session.hasSession ? session.mode : NotchTimerSupport.savedMode(),
                hasSession: session.hasSession, width: size.width, height: size.height))
        case .calendar:
            size.height = max(size.height, NotchLayout.calendarMonthMinimumHeight)
        case .clipboard:
            // Search, spacing and a complete card with its action row.
            size.height = max(size.height, NotchLayout.clipboardSearchHeight + NotchLayout.rowSpacing
                              + NotchLayout.clipboardCardHeight)
        case .camera:
            // Keep permission and error messages, and the stop button, reachable.
            size.height = max(size.height, 144)
        case .mixer:
            // Shorten the tracks before pushing mute and level controls offscreen.
            size.height = max(size.height, 144)
        case .music:
            let controlsRow = AppFeature.mixer.isAvailable || NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
                ? NotchLayout.musicControlsRowHeight + NotchLayout.rowSpacing : 0
            let player = music.playback == nil ? NotchLayout.musicIdleHeight
                : max(NotchLayout.musicMinimumPlayerHeight,
                      NotchLayout.musicPlayerHeight(layout: service.geometry.layout, height: size.height))
            let sourceTabs = music.playback != nil && music.sources.count > 1 ? NotchLayout.musicSourcePagerExtent : 0
            size.height = max(size.height, player + controlsRow + sourceTabs)
        case .files:
            // One shelf tile, its vertical insets, the footer and their gap.
            size.height = max(size.height, 88 + 8 + 28 + NotchLayout.rowSpacing)
        default: break
        }
        return size
    }

    private var contentOverflows: Bool { pageSize.height > service.expandedViewContentSize.height }

    private var scrollsVertically: Bool {
        guard !service.showingAppPanel else { return false }
        return contentOverflows || service.selectedMetric != nil
            || (service.selected == .captures && service.captureContent != nil)
            || (service.selected == .tools && launcher.isEditing && launcher.activeUtility == nil)
    }

    private var headerFeedback: NotchNotice? {
        guard let notice = service.notice, notice.level != nil,
              [.volume, .brightness, .keyboardLight].contains(notice.event) else { return nil }
        return notice
    }

    private var header: some View {
        HStack(spacing: service.expandedViewGeometry.headerCameraGap > 0 ? 0 : 6) {
            let quickActions = service.expandedQuickAccess.actions
            HStack(spacing: 6) {
                if service.showingSections {
                    NotchIconButton(symbol: "chevron.left", title: l10n.s.obBack, action: service.toggleSections)
                    if service.expandedViewGeometry.headerCameraGap == 0 {
                        Text(text.sectionsTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    // Beside the camera the field takes the rest of its side,
                    // stopping a little short of the cutout.
                    NotchSectionSearch(service: service,
                                       maximumFieldWidth: service.expandedViewGeometry.headerCameraGap > 0 ? .infinity : 150)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if showsDetail || service.modules.isEmpty {
                    if showsDetail {
                        NotchIconButton(symbol: "chevron.left", title: l10n.s.obBack, action: service.goBack)
                    }
                    Text(service.detailTitle)
                        .font(Font(NotchLayout.detailTitleFont as CTFont))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    if !quickActions.contains(.explore) {
                        NotchIconButton(symbol: "square.grid.2x2", title: text.sectionsTitle, action: service.toggleSections)
                    }
                    Text(service.selected.title(l10n.language))
                        .font(Font(NotchLayout.headerTitleFont as CTFont))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.trailing, service.expandedViewGeometry.headerCameraGap > 0 ? NotchLayout.cameraClearance : 0)
            .frame(width: service.expandedViewGeometry.headerCameraGap > 0 ? (service.expandedViewContentSize.width - service.expandedViewGeometry.headerCameraGap) / 2 : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep search mounted so a media key never discards its focus.
            .opacity(headerFeedback == nil ? 1 : 0)
            .allowsHitTesting(headerFeedback == nil)
            .accessibilityHidden(headerFeedback != nil)
            .overlay(alignment: .leading) {
                if let notice = headerFeedback {
                    NotchExpandedLevelView(notice: notice)
                        .padding(.trailing, service.expandedViewGeometry.headerCameraGap > 0 ? NotchLayout.cameraClearance : 0)
                }
            }
            .clipped()
            if service.expandedViewGeometry.headerCameraGap > 0 {
                Color.clear.frame(width: service.expandedViewGeometry.headerCameraGap)
            }
            HStack(spacing: 6) {
                if service.selected == .captures, !showsDetail, !service.showingSections,
                   let actions = service.captureActions {
                    actions.fixedSize()
                    overflowMenu(items: overflowItems(tools: false, clear: false))
                } else if service.expandedViewGeometry.headerCameraGap > 0 {
                    cameraHeaderActions
                } else {
                    headerActions(quickActions: quickActions)
                }
            }
            .padding(.leading, service.expandedViewGeometry.headerCameraGap > 0 ? NotchLayout.cameraClearance : 0)
            .frame(width: service.expandedViewGeometry.headerCameraGap > 0 ? (service.expandedViewContentSize.width - service.expandedViewGeometry.headerCameraGap) / 2 : nil,
                   alignment: .trailing)
        }
        .frame(height: service.expandedViewGeometry.headerRowHeight)
        .contentShape(Rectangle())
        .onHover { headerHovered = $0 }
        .onAppear { UpdateService.shared.checkIfStale() }
        // Collapsing under the pointer takes the row away without a final
        // hover(false); the next opening starts with the actions out of sight.
        .onDisappear { headerHovered = false }
    }

    /// The island's history page shows only the cards, so its clear action
    /// sits in the header, where the panel's own header keeps it.
    private var showsCapturesClear: Bool {
        service.selected == .captures && service.captureContent == nil && !showsDetail
            && !service.showingSections && !service.modules.isEmpty
    }

    private var cameraHeaderActions: some View {
        ViewThatFits(in: .horizontal) {
            cameraHeaderActions(compactUpdate: false).fixedSize(horizontal: true, vertical: false)
            cameraHeaderActions(compactUpdate: true).fixedSize(horizontal: true, vertical: false)
        }
    }

    private func cameraHeaderActions(compactUpdate: Bool) -> some View {
        HStack(spacing: 6) {
            NotchUpdateControl(action: service.showUpdate, compact: compactUpdate)
            overflowMenu(items: overflowItems(
                tools: service.selected == .tools && !showsDetail && !service.showingSections && launcher.activeUtility == nil,
                clear: showsCapturesClear))
        }
    }

    /// The header's overflow entries, each with the glyph its own button
    /// wears when the pointer row shows them separately.
    private func overflowItems(tools: Bool, clear: Bool) -> [NotchMenuItem] {
        var items: [NotchMenuItem] = []
        if tools {
            items.append(NotchMenuItem(title: text.customizeTools, checked: launcher.isEditing,
                                       symbol: "slider.horizontal.3") { launcher.isEditing.toggle() })
        }
        if clear {
            // As the header draws, the pointer on its way to this menu included,
            // and again when chosen: this view does not observe the history.
            let empty = { RecentCapturesView.visible(RecentCaptureService.shared.entries).isEmpty }
            items.append(NotchMenuItem(title: FeatureStrings.recentCaptures(l10n.language).clear, symbol: "trash",
                                       enabled: !empty(), action: {
                guard !empty() else { return }
                RecentCapturesView.confirmClearAboveIsland()
            }))
        }
        if !items.isEmpty { items.append(.separator) }
        items.append(NotchMenuItem(title: service.pinned ? text.unpin : text.pin,
                                   symbol: service.pinned ? "pin.slash" : "pin") { service.pinned.toggle() })
        items.append(NotchMenuItem(title: l10n.s.menuSettings, symbol: "gearshape", action: service.openSettings))
        items.append(NotchMenuItem(title: text.collapse, symbol: "chevron.up", action: service.collapse))
        return items
    }

    /// A native menu drawn in the island's dark appearance, so it reads as part
    /// of it, and each entry carries its glyph.
    private func overflowMenu(items: [NotchMenuItem]) -> some View {
        NotchMenuButton(title: text.title, items: items, cornerRadius: 8) {
            Image(systemName: service.pinned ? "pin.fill" : "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// The header's actions keep their room but stay out of sight until the
    /// pointer reaches the row: a title, not a toolbar. An available update
    /// leaves a dot so it is never missed, and a download stays in view.
    /// The fade follows the value instead of the hover callback's transaction,
    /// which reached the screen without its animation once the island was key.
    private func headerActions(quickActions: [NotchQuickAction]) -> some View {
        let updating = updates.state.isInProgress
        let revealed = headerHovered || updating
        return HStack(spacing: 6) {
            NotchUpdateControl(action: service.showUpdate)
            if service.selected == .tools, !service.showingAppPanel, !service.showingSections, service.selectedMetric == nil,
               !service.modules.isEmpty, launcher.activeUtility == nil {
                NotchIconButton(symbol: launcher.isEditing ? "checkmark" : "slider.horizontal.3",
                                title: text.customizeTools, selected: launcher.isEditing) {
                    withAnimation(.easeOut(duration: 0.15)) { launcher.isEditing.toggle() }
                }
            }
            if showsCapturesClear { NotchClearCapturesButton() }
            // Keeping the island open is one click, like the floating buttons;
            // a header button steps aside when the same action floats beside it.
            if !quickActions.contains(.pin) {
                NotchIconButton(symbol: service.pinned ? "pin.fill" : "pin",
                                title: service.pinned ? text.unpin : text.pin, selected: service.pinned) {
                    service.pinned.toggle()
                }
            }
            if !quickActions.contains(.settings) {
                NotchIconButton(symbol: "gearshape", title: l10n.s.menuSettings, action: service.openSettings)
            }
            NotchIconButton(symbol: "chevron.up", title: text.collapse, action: service.collapse)
        }
        .opacity(revealed ? 1 : 0)
        .overlay(alignment: .trailing) {
            if !revealed {
                HStack(spacing: 5) {
                    if case .available(let version) = updates.state {
                        Circle()
                            .fill(UpdateServiceSupport.SemanticVersion(raw: version)?.isPrerelease == true ? Color.orange : Color.blue)
                            .frame(width: 6, height: 6)
                    }
                    // A kept-open island says so at rest, not only under the pointer.
                    if service.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 28, height: 28)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: revealed)
    }

    private var navigationTitle: String {
        let destination = service.reopeningDestination
        return destination.appPanel || destination.sections
            ? text.sectionsTitle : destination.module.title(l10n.language)
    }

    private var navigation: some View {
        Button(action: service.toggleSections) {
            HStack(spacing: 9) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(navigationTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: NotchLayout.navigationHeight)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12, lifts: false))
        .accessibilityLabel(text.switchSection)
        .accessibilityValue(navigationTitle)
        .accessibilityIdentifier("notch.navigation")
        .help(text.switchSection + "  ⌘K")
    }

    @ViewBuilder private var content: some View {
        if service.showingAppPanel {
            MenuPanelView(notchSize: pageSize)
        } else if let metric = service.selectedMetric {
            if metric == .fan {
                NotchFanControlView()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { service.updateFanDetailHeight($0) }
            } else {
                MetricDetailView(kind: metric)
            }
        } else if service.modules.isEmpty {
            NotchEmptyView(symbol: "slider.horizontal.3", message: text.empty)
        } else {
            switch service.selected {
            case .timer: NotchTimerView(size: pageSize)
            case .camera: NotchCameraView(size: pageSize)
            case .notifications: NotchNotificationsView(size: pageSize)
            case .downloads: NotchDownloadsView(size: pageSize)
            case .calendar: NotchCalendarView(size: pageSize)
            case .controls: NotchControlsView(service: service, size: pageSize)
            case .mixer: NotchMixerView(size: pageSize)
            case .music: NotchMusicView(size: pageSize, extrasHeight: service.geometry.musicExtrasHeight)
            case .clipboard: NotchClipboardView(service: service, size: pageSize)
            case .dictation: DictationHistoryView(compact: true)
            case .captures:
                if let capture = service.captureContent {
                    capture.frame(maxWidth: .infinity)
                } else {
                    RecentCapturesView(onClose: nil, notchSize: pageSize)
                }
            case .files: NotchFilesView(service: service)
            case .system:
                NotchSystemView(size: pageSize) { service.showMetric($0) }
            case .tools: QuickLauncherView(notchSize: pageSize)
            case .scratchpad: NotchScratchpadView(service: service)
            case .agents: NotchAgentsView(size: pageSize)
            case .watch: NotchWatchView(size: pageSize)
            }
        }
    }
}

/// Observes the history on its own, so a new capture does not redraw the island.
private struct NotchClearCapturesButton: View {
    @ObservedObject private var history = RecentCaptureService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        NotchIconButton(symbol: "trash", title: FeatureStrings.recentCaptures(l10n.language).clear,
                        action: RecentCapturesView.confirmClearAboveIsland)
            .disabled(RecentCapturesView.visible(history.entries).isEmpty)
    }
}

/// Read-only RPM telemetry stays available when the protected fan helper fails.
private struct NotchFanControlView: View {
    @ObservedObject private var monitor = SystemMonitor.shared

    var body: some View {
        FanControlSection(collapsible: false, fallbackFanSpeeds: monitor.snapshot.fanSpeeds)
    }
}

private extension UpdateService.State {
    /// A download or install stays in view; an offer waits behind the dot.
    var isInProgress: Bool {
        switch self {
        case .downloading, .installing: return true
        default: return false
        }
    }
}

/// The closed island at rest beside a camera: the wings with the charge,
/// the song or the AI allowance the person chose, when the menus leave room.
struct NotchRestingStrip: View {
    @ObservedObject var service: NotchService
    /// Another display's strip, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var music = NotchMusicService.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.geometry }

    /// Centre battery content inside the wing's visible area, past its curved shoulder.
    private var restingBatteryInset: CGFloat {
        // Leave enough of the 44-point wing for the full 100% label at every height.
        min(16, NotchLayout.shoulder(height: geometry.stripHeight) + NotchLayout.compactEdgeGap)
    }

    var body: some View {
        HStack(spacing: 0) {
            if service.idleContent != .none, geometry.restingWingWidth > 0 {
                Group {
                    switch service.idleContent {
                    case .music:
                        if let artwork = music.artwork {
                            Image(nsImage: artwork).resizable().scaledToFill()
                                .frame(width: min(22, geometry.stripHeight - 6), height: min(22, geometry.stripHeight - 6))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    case .battery:
                        Image(systemName: "battery.100percent").font(.system(size: 12))
                            .padding(.leading, restingBatteryInset)
                    case .agents:
                        NotchAgentRestingWing(leading: true)
                            .padding(.leading, restingBatteryInset)
                    case .none: EmptyView()
                    }
                }.frame(width: geometry.restingWingWidth, alignment: .trailing)
                Color.clear.frame(width: geometry.cameraWidth)
                Group {
                    switch service.idleContent {
                    case .music:
                        if music.playback?.isPlaying == true {
                            NotchLiveEqualizerBars(bars: 3, barWidth: 2, height: 11,
                                                   tint: music.artworkTint?.color ?? .white)
                        }
                    case .battery:
                        if let percent = service.power.chargePercent {
                            Text("\(percent)%").font(.system(size: 9, weight: .medium)).monospacedDigit()
                                .lineLimit(1)
                                .padding(.trailing, restingBatteryInset)
                        }
                    case .agents:
                        NotchAgentRestingWing(leading: false)
                            .padding(.trailing, restingBatteryInset)
                    case .none: EmptyView()
                    }
                }.frame(width: geometry.restingWingWidth, alignment: .leading)
            } else { Color.clear }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

struct NotchShape: Shape {
    var attached: Bool
    var radius: CGFloat
    /// A capsule floating this far inside the top and bottom of the rect,
    /// with its own corners, instead of the outline hanging from the edge.
    var floatingGap: CGFloat? = nil
    /// A camera-level meter stretches the existing cutout's edge profile;
    /// growing its shoulders with height would pinch its visible side walls.
    var profileHeight: CGFloat? = nil
    var minimumBodyWidth: CGFloat = 0
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    /// The island's outline at a surface of `height`, as its display draws it.
    static func island(height: CGFloat, geometry: NotchGeometry) -> NotchShape {
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: height), floatingGap: geometry.floatingGap)
    }

    func path(in rect: CGRect) -> Path {
        guard attached else { return Path(roundedRect: rect, cornerRadius: radius) }
        if let floatingGap { return Path(NotchLayout.capsulePath(in: rect, gap: floatingGap)) }
        var shoulder = NotchLayout.shoulder(height: profileHeight ?? rect.height)
        if minimumBodyWidth > 0 {
            let room = max(0, (rect.width - minimumBodyWidth) / 2)
            // A soft limit keeps the body clear of the camera without a kink
            // where a hard clamp would suddenly start moving the side walls.
            shoulder = room + shoulder > 0 ? room * shoulder / (room + shoulder) : 0
        }
        let bottom = min(radius, rect.height / 2, (rect.width - shoulder * 2) / 2)
        let tangent: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addCurve(to: CGPoint(x: rect.width - shoulder, y: shoulder),
                      control1: CGPoint(x: rect.width - shoulder * tangent, y: 0),
                      control2: CGPoint(x: rect.width - shoulder, y: shoulder * (1 - tangent)))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - bottom))
        path.addCurve(to: CGPoint(x: rect.width - shoulder - bottom, y: rect.height),
                      control1: CGPoint(x: rect.width - shoulder, y: rect.height - bottom * (1 - tangent)),
                      control2: CGPoint(x: rect.width - shoulder - bottom * (1 - tangent), y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + bottom, y: rect.height))
        path.addCurve(to: CGPoint(x: shoulder, y: rect.height - bottom),
                      control1: CGPoint(x: shoulder + bottom * (1 - tangent), y: rect.height),
                      control2: CGPoint(x: shoulder, y: rect.height - bottom * (1 - tangent)))
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addCurve(to: .zero,
                      control1: CGPoint(x: shoulder, y: shoulder * (1 - tangent)),
                      control2: CGPoint(x: shoulder * tangent, y: 0))
        path.closeSubpath()
        return path
    }
}

extension NotchModule: PanelOrderItem {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .timer: return FeatureStrings.notchActivities(language).timer
        case .camera: return FeatureStrings.notchActivities(language).camera
        case .notifications: return FeatureStrings.notchNotifications(language).title
        case .downloads: return FeatureStrings.notchFiles(language).downloadsTitle
        case .calendar: return FeatureStrings.notchCalendar(language).title
        case .controls: return FeatureStrings.notch(language).controls
        case .mixer: return Strings.localized(language).mixerSection
        case .music: return FeatureStrings.radialMenu(language).mediaNowPlaying
        case .clipboard: return FeatureStrings.clipboard(language).title
        case .dictation: return DictationStrings.localized(language).title
        case .captures: return FeatureStrings.recentCaptures(language).title
        case .files: return FeatureStrings.notch(language).files
        case .system: return FeatureStrings.notch(language).system
        case .tools: return FeatureStrings.notch(language).tools
        case .scratchpad: return FeatureStrings.scratchpad(language).pageTitle
        case .agents: return FeatureStrings.notchAgents(language).title
        case .watch: return FeatureStrings.notchWatch(language).title
        }
    }
}

/// A page may draw into the island's own margins and behind its header, which
/// the silhouette already bounds: the artwork's halo and hover growth fade out
/// there instead of ending at a hard edge. The header stays above the page.
private struct NotchPageClip: Shape {
    /// From the top of the page to the top of the island.
    let top: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - NotchLayout.horizontalInset, y: rect.minY - top,
                    width: rect.width + NotchLayout.horizontalInset * 2,
                    height: rect.height + top + NotchLayout.bottomInset))
    }
}

/// The strip the picker shows, a new one for each choice.
private struct NotchPickedStrip: Hashable {
    let activity: NotchCompactActivity
    let companion: NotchCompactActivity?
}

/// Named choices appear below the camera, with the current activity highlighted.
struct NotchActivityPicker: View {
    @Namespace private var choice
    let activities: [NotchCompactActivity]
    let selected: NotchCompactActivity
    let combinations: [NotchActivityCombination]
    let combination: NotchActivityCombination?
    let columns: Int
    let language: AppLanguage
    let select: (NotchCompactActivity) -> Void
    let combine: (NotchActivityCombination) -> Void

    var body: some View {
        VStack(spacing: NotchActivityPickerLayout.spacing) {
            individualChoices
            if !combinations.isEmpty {
                Menu {
                    ForEach(combinations) { pair in
                        Button { combine(pair) } label: {
                            Label(pair.title(language),
                                  systemImage: combination == pair ? "checkmark" : pair.companion.symbol)
                        }
                    }
                } label: {
                    Label(combination?.title(language) ?? FeatureStrings.notch(language).combineActivities,
                          systemImage: combination == nil ? "plus" : "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(combination == nil ? 0.75 : 1))
                        .frame(height: NotchActivityPickerLayout.combinationHeight)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("notch.activity.combine")
            }
        }
    }

    private var individualChoices: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NotchActivityPickerLayout.spacing),
                                 count: columns), spacing: NotchActivityPickerLayout.spacing) {
            ForEach(activities) { activity in
                let chosen = activity == selected && combination == nil
                Button { select(activity) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: activity.symbol)
                        Text(activity.title(language)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: NotchActivityPickerLayout.rowHeight)
                    .foregroundStyle(chosen ? Color.black : Color.white)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12))
                            if chosen {
                                RoundedRectangle(cornerRadius: 8).fill(Color.white)
                                    .matchedGeometryEffect(id: "choice", in: choice)
                            }
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(activity.title(language))
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("notch.activity.\(activity.rawValue)")
            }
        }
    }
}

/// A stable card viewport reveals a page already laid out at its destination
/// size, keeping expensive page layout out of the animation's frame loop.
struct NotchActivityViewport: ViewModifier {
    let targetSize: CGSize
    let geometry: NotchGeometry
    let focused: Bool
    let targetX: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var widthMotion: NotchSpringChannel
    @State private var heightMotion: NotchSpringChannel
    @State private var positionMotion: NotchSpringChannel
    @State private var started: Date = .distantPast
    @State private var moving = false
#if VORSSAINT_DEVELOPMENT
    /// Observe the painted viewport inside its offset, not the unshifted
    /// layout bounds SwiftUI reports outside an offset modifier.
    var motionProbe: ((CGRect) -> Void)? = nil
#endif

    init(size: CGSize, x: CGFloat = 0, geometry: NotchGeometry, focused: Bool = false) {
        targetSize = size
        targetX = x
        _widthMotion = State(initialValue: NotchSpringChannel(size.width))
        _heightMotion = State(initialValue: NotchSpringChannel(size.height))
        _positionMotion = State(initialValue: NotchSpringChannel(x))
        self.geometry = geometry
        self.focused = focused
    }

    private func pose(at date: Date) -> (size: CGSize, x: CGFloat) {
        guard moving else { return (CGSize(width: widthMotion.target, height: heightMotion.target), positionMotion.target) }
        let elapsed = max(0, date.timeIntervalSince(started))
        return (CGSize(width: max(0, widthMotion.sample(at: elapsed).value),
                       height: max(0, heightMotion.sample(at: elapsed).value)), positionMotion.sample(at: elapsed).value)
    }

    private func outline(height: CGFloat) -> NotchShape {
        var shape = NotchShape.island(height: height, geometry: geometry)
        if focused && geometry.isNotched { shape.minimumBodyWidth = geometry.physicalCameraWidth }
        return shape
    }

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !moving)) { clock in
            let value = pose(at: clock.date)
            let outline = outline(height: value.size.height)
        content
            .frame(width: targetSize.width, height: targetSize.height, alignment: .top)
            .transaction { $0.animation = nil }
            .frame(width: value.size.width, height: value.size.height, alignment: .top)
            .clipShape(outline)
            .background {
#if VORSSAINT_DEVELOPMENT
                if let motionProbe {
                    outline.fill(.black)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("activityMotionStage")) } action: { motionProbe($0) }
                } else { outline.fill(.black) }
#else
                outline.fill(.black)
#endif
            }
            .overlay {
                outline.stroke(.white.opacity(focused ? 0.13 : 0.08), lineWidth: 0.5)
            }
            .contentShape(outline)
            // Position and dimensions share one clock and spring state.
            // A side card cannot snap to its closed centre before it shrinks.
            .offset(x: value.x)
            // Interpolation belongs to this modifier. Its child frames snap
            // to each interpolated viewport, without starting another spring.
            .transaction { $0.animation = nil }
        }
        .onChange(of: CGRect(x: targetX, y: 0, width: targetSize.width, height: targetSize.height)) {
#if VORSSAINT_DEVELOPMENT
            NotchHoverTrace.mark("viewport motion started")
#endif
            let now = Date()
            let elapsed = moving ? max(0, now.timeIntervalSince(started)) : 2
            let current = pose(at: now)
            let widthSpring = NotchMotion.spring(from: current.size.width, to: targetSize.width, width: true)
            widthMotion.retarget(targetSize.width, at: elapsed, spring: widthSpring)
            heightMotion.retarget(targetSize.height, at: elapsed,
                                  spring: NotchMotion.spring(from: current.size.height, to: targetSize.height, width: false))
            // Shared width/position spring preserves a side pill's inner edge.
            positionMotion.retarget(targetX, at: elapsed, spring: current.size.width != targetSize.width
                ? widthSpring : NotchMotion.spring(from: abs(current.x), to: abs(targetX), width: true))
            started = now
            moving = !reduceMotion
            if reduceMotion {
                widthMotion = NotchSpringChannel(targetSize.width)
                heightMotion = NotchSpringChannel(targetSize.height)
                positionMotion = NotchSpringChannel(targetX)
            }
            let token = now
            let settling = max(widthMotion.settlingTime, heightMotion.settlingTime, positionMotion.settlingTime)
            DispatchQueue.main.asyncAfter(deadline: .now() + settling) {
                guard started == token else { return }
                moving = false
            }
        }
    }
}

struct NotchPillDeckRow<Left: View, Primary: View, Right: View>: View {
    let size: CGSize
    let primaryWidth: CGFloat
    @ViewBuilder let left: () -> Left
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let right: () -> Right

    var body: some View {
        let side = max(0, (size.width - primaryWidth) / 2 - NotchPillActivityLayout.spacing)
        HStack(alignment: .top, spacing: side > 0 ? NotchPillActivityLayout.spacing : 0) {
            left().frame(width: side, alignment: .trailing)
            primary().frame(width: primaryWidth)
            right().frame(width: side, alignment: .leading)
        }
        .frame(width: size.width, height: size.height)
    }
}

struct NotchPillAgentCompactContent: View {
    let providers: [AgentProvider]
    let reading: String
    let geometry: NotchGeometry

    var body: some View {
        HStack(spacing: NotchCapsuleLayout.spacing) {
            HStack(spacing: NotchCapsuleLayout.agentCompactMarkSpacing) {
                ForEach(providers) { provider in
                    NotchAgentGlyph(provider: provider, size: NotchCapsuleLayout.agentCompactGlyphSize(geometry))
                }
                if providers.isEmpty {
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(reading).font(Font(NotchCapsuleLayout.agentCompactFont as CTFont))
                .lineLimit(1).fixedSize()
        }
        .foregroundStyle(providers.first?.tint ?? .cyan)
        .padding(.horizontal, NotchCapsuleLayout.side(geometry) + NotchCapsuleLayout.endPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NotchAttachedActivityContent<Mark: View, Signal: View>: View {
    let geometry: NotchGeometry
    @ViewBuilder let mark: () -> Mark
    @ViewBuilder let signal: () -> Signal

    var body: some View {
        HStack(spacing: 0) {
            mark().fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: NotchAttachedActivityLayout.contentGap)
            signal().fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, NotchCapsuleLayout.side(geometry) + NotchAttachedActivityLayout.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NotchPillCompactMark: View {
    let activity: NotchCompactActivity
    let geometry: NotchGeometry
    var physicalSide = false
    var onReadingShapeChange: () -> Void = {}
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var watch = NotchWatchService.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var calendar = NotchCalendarService.shared

    private var tint: Color {
        switch activity {
        case .timer: return .orange
        case .agents: return usage.snapshot.live.first?.provider.tint ?? .cyan
        case .calendar: return .mint
        case .keepAwake: return .yellow
        default: return .white
        }
    }

    var body: some View {
        Group {
            if activity == .agents {
                NotchAgentReadoutTimeline(readout: .elapsed) { now in
                    let providers = AgentProvider.allCases.filter { provider in
                        usage.snapshot.live.contains { $0.provider == provider }
                    }
                    let reading = NotchAgentSupport.stripReading(usage.snapshot, readout: .elapsed,
                                                                 display: .remaining, now: now)
                    Group {
                        if physicalSide {
                            NotchAttachedActivityContent(geometry: geometry) {
                                HStack(spacing: 5) {
                                    ForEach(providers) { provider in
                                        NotchAgentGlyph(provider: provider, size: NotchAttachedActivityLayout.agentMarkSize)
                                            .foregroundStyle(provider.tint)
                                    }
                                    if providers.isEmpty { Image(systemName: "sparkles") }
                                }
                            } signal: { sideReading(reading) }
                        } else {
                            NotchPillAgentCompactContent(providers: providers, reading: reading, geometry: geometry)
                        }
                    }
                        .onChange(of: NotchAgentSupport.readingShape(reading)) { _, _ in
                            DispatchQueue.main.async { onReadingShapeChange() }
                        }
                }
            } else if activity == .call {
                NotchCallStrip(geometry: geometry, size: CGSize(width: 100, height: geometry.stripHeight), minimal: true)
            } else if physicalSide {
                NotchAttachedActivityContent(geometry: geometry) { mark } signal: { signal }
            } else {
                HStack(spacing: activity == .music ? 9 : 4) { mark; signal }
            }
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var mark: some View {
        switch activity {
        case .music:
            let side = physicalSide ? NotchAttachedActivityLayout.markSize : min(14, NotchCapsuleLayout.artworkSide(geometry))
            NotchMusicCover(artwork: music.artwork, side: side, radius: min(2, side * 0.16))
        case .agents:
            EmptyView() // The complete provider group and clock are rendered together above.
        case .call:
            EmptyView()
        case .watch:
            NotchWatchEye(size: physicalSide ? 15 : 13, hidden: watch.state == .hidden)
        case .keepAwake:
            Image(systemName: NotchKeepAwakeSupport.symbol).font(.system(size: physicalSide ? 14 : 12, weight: .medium))
        default:
            Image(systemName: activity.symbol).font(.system(size: physicalSide ? 14 : 12, weight: .medium))
        }
    }

    @ViewBuilder private var signal: some View {
        switch activity {
        case .music:
            NotchLiveEqualizerBars(isPlaying: music.playback?.isPlaying == true,
                                   bars: physicalSide ? 3 : 2, barWidth: 1.5, height: physicalSide ? 12 : 9,
                                   tint: music.artworkTint?.color ?? .white)
        case .downloads:
            let fraction = downloads.items.first { $0.active && !$0.completed }?.fraction ?? 0
            ZStack {
                if physicalSide { Circle().stroke(.white.opacity(0.18), lineWidth: 2) }
                Circle().trim(from: 0, to: max(0.02, fraction))
                    .stroke(.white, style: StrokeStyle(lineWidth: physicalSide ? 2 : 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }.frame(width: physicalSide ? 14 : 9, height: physicalSide ? 14 : 9)
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let reading = NotchTimerSupport.compactText(for: timer.session, at: timer.now, locale: .current)
                if physicalSide { sideReading(reading) }
                else { Text(reading)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .lineLimit(1) }
            }
        case .agents:
            EmptyView()
        case .call:
            EmptyView()
        case .calendar:
            if physicalSide, let countdown = calendar.countdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    sideReading(NotchCalendarSupport.countdownText(until: countdown.target, now: context.date))
                }
            } else { Circle().fill(.mint).frame(width: 6, height: 6) }
        case .watch:
            Circle().fill(watch.state == .hidden ? Color.secondary : Color.green).frame(width: 6, height: 6)
        case .keepAwake:
            if physicalSide, let end = awake.endDate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    sideReading(NotchKeepAwakeSupport.compactText(until: end, now: context.date, locale: .current))
                }
            } else {
                Image(systemName: awake.endDate == nil ? "infinity" : "clock")
                    .font(.system(size: physicalSide ? 12 : 8, weight: .medium))
            }
        }
    }

    private func sideReading(_ reading: String) -> some View {
        Text(reading).font(Font(NotchAttachedActivityLayout.readoutFont as CTFont))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1).fixedSize()
            .onChange(of: NotchAgentSupport.readingShape(reading)) { _, _ in
                DispatchQueue.main.async { onReadingShapeChange() }
            }
    }
}
