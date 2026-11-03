// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchCustomizationCatalogTests {
    static func run(_ suite: TestSuite) {
        let actions = NotchCustomizationCatalog.extensionActions
        suite.expect(Set(actions.map(\.id)).count == actions.count,
                     "the extension chooser has unique canonical action IDs")
        for page in NotchModule.allCases {
            suite.expect(actions.contains(.module(page)), "every island page can be placed around the island: \(page.rawValue)")
            if page != .controls {
                suite.expect(NotchControlItem.allCases.contains { $0.destinationModule == page || (page == .scratchpad && $0 == .scratchpad) },
                             "every non-recursive island page has a Control Center destination: \(page.rawValue)")
            }
        }
        for tool in QuickLauncherContract.QuickLauncherItem.allCases {
            suite.expect(NotchControlItem.allCases.contains { control in
                control.utilityFeature == tool.feature || control.destinationModule?.requiredFeature == tool.feature
                    || control.setupRequirement == .feature(tool.feature)
            }, "each quick-panel utility has a corresponding island customization choice: \(tool.rawValue)")
        }
        suite.expect(NotchQuickAction.control(.mixer).canonical == .module(.mixer)
                     && NotchQuickAction.control(.dictate).canonical == .control(.dictate),
                     "legacy page aliases are highlighted canonically while genuine actions retain their identity")
        for item in NotchControlItem.allCases {
            suite.expect(NotchQuickAction(id: "control." + item.rawValue) == .control(item),
                         "saved control IDs remain decodable: \(item.rawValue)")
            if item.destinationModule == nil { suite.expect(actions.contains(.control(item)), "every direct action is offered to extensions: \(item.rawValue)") }
        }

        let registration = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        defer { UserDefaults.standard.setVolatileDomain(registration, forName: UserDefaults.registrationDomain) }
        let domain = "com.vorssaint.tests.island-catalog"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defaults.register(defaults: Defaults.registeredDefaults)
        defaults.register(defaults: Dictionary(uniqueKeysWithValues: AppFeature.allCases.map { ($0.availabilityKey, true) }))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: AppFeature.screenshot.availabilityKey)
        suite.expect(NotchModule.captures.isAvailable(in: defaults) && NotchModule.captures.setupFeature(in: defaults) == nil,
                     "captures setup accepts alternate sources without requiring screenshots")
        defaults.set(true, forKey: AppFeature.screenshot.availabilityKey)
        defaults.set("volume,brightness", forKey: DefaultsKey.notchHiddenControls)
        defaults.set("timer,music", forKey: DefaultsKey.notchControlOrder)
        let legacyVisible = NotchSupport.controls(in: defaults).filter { !NotchControlItem.additionalItems.contains($0) }
        let custom = NotchQuickAccessConfiguration(buttons: [NotchQuickButton(action: .control(.mixer), side: .left, label: "My mixer")])
        defaults.set(custom.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        NotchControlItem.migrateAdditionalItems(in: defaults)
        suite.expect(NotchSupport.controls(in: defaults) == legacyVisible,
                     "catalog migration keeps the exact existing visible controls and order")
        suite.expect(NotchQuickAccessConfiguration.stored(in: defaults) == custom,
                     "catalog migration leaves custom extension IDs, labels, and positions untouched")
        let migrated = defaults.string(forKey: DefaultsKey.notchHiddenControls)!
        let optedIn = migrated.split(separator: ",").filter { $0 != Substring(NotchControlItem.files.rawValue) }.joined(separator: ",")
        defaults.set(optedIn, forKey: DefaultsKey.notchHiddenControls)
        NotchControlItem.migrateAdditionalItems(in: defaults)
        suite.expect(defaults.string(forKey: DefaultsKey.notchHiddenControls) == optedIn,
                     "the one-time migration never hides a new control deliberately enabled later")

        func restore(_ settings: [String: Any]) -> [String: Any] {
            SettingsBackupSupport.sanitizedSettings(from: [SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion, SettingsBackupSupport.settingsKey: settings]) ?? [:]
        }
        let old = restore([DefaultsKey.notchHiddenControls: "volume", DefaultsKey.notchControlOrder: "music"])
        let oldHidden = Set((old[DefaultsKey.notchHiddenControls] as? String ?? "").split(separator: ",").map(String.init))
        suite.expect(oldHidden.isSuperset(of: NotchControlItem.additionalItems.map(\.rawValue)) && oldHidden.contains("volume"),
                     "importing an older backup cannot silently enable newly introduced controls")
        let current = restore([DefaultsKey.notchHiddenControls: optedIn, DefaultsKey.notchUnifiedControlsInitialized: true])
        suite.expect(current[DefaultsKey.notchHiddenControls] as? String == optedIn,
                     "a current backup preserves explicit new control choices")
    }
}
