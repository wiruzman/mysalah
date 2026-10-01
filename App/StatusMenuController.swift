import AppKit
import SwiftUI
import ServiceManagement
import MySalahCore

@MainActor private final class MenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke(_ sender: NSMenuItem) { action() }
}

@MainActor private final class LocationMenu: NSMenu {
    enum Level {
        case countries
        case regions(Place)
        case districts(Place, Place)
        var cacheKey: String {
            switch self { case .countries: "countries"; case .regions(let country): "regions-\(country.id)"; case .districts(_, let region): "districts-\(region.id)" }
        }
    }
    let level: Level
    var loading = false
    var loaded = false
    init(level: Level) { self.level = level; super.init(title: ""); autoenablesItems = false }
    required init(coder: NSCoder) { fatalError("Location menus are created programmatically") }
}

private struct CachedPlaces: Codable, Sendable {
    let date: Date
    let places: [Place]
}

@MainActor final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    private let catalogCache = DiskCache()
    private var catalogs: [String: [Place]] = [:]
    private var tracking = false
    private var secondsTimer: Timer?
    private var boundaryTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.delegate = self; menu.autoenablesItems = false
        item.menu = menu
        item.button?.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "MySalah")
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        model.onMenuNeedsUpdate = { [weak self] in
            guard let self else { return }
            applyTheme(); updateStatus()
            if !tracking { rebuildMenu() }
        }
        let wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.wake(); self?.updateStatus() }
        }
        observers.append(wake)
        for name in [NSNotification.Name.NSSystemClockDidChange, NSNotification.Name.NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.wake(); self?.updateStatus() }
            })
        }
        applyTheme(); rebuildMenu(); updateStatus()
    }
    private var strings: Localizer { model.strings }
    func stop() {
        secondsTimer?.invalidate(); boundaryTimer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        model.onMenuNeedsUpdate = nil
        NSStatusBar.system.removeStatusItem(item)
    }
    private func applyTheme() {
        switch model.preferences.theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // The status button lives on system chrome, which may differ from the forced app theme.
        item.button?.appearance = nil
    }
    private func action(_ title: String, selected: Bool? = nil, key: String = "", run: @escaping () -> Void) -> NSMenuItem {
        let handler = MenuAction(run)
        let result = NSMenuItem(title: title, action: #selector(MenuAction.invoke(_:)), keyEquivalent: key)
        result.target = handler; result.representedObject = handler
        if let selected { result.state = selected ? .on : .off }
        return result
    }
    private func label(_ title: String) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: nil, keyEquivalent: ""); result.isEnabled = false; return result
    }
    private func submenu(_ title: String, to parent: NSMenu) -> NSMenu {
        let child = NSMenu(title: title); child.autoenablesItems = false
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: ""); entry.submenu = child; parent.addItem(entry)
        return child
    }
    private func boolChoices(in menu: NSMenu, value: Bool, set: @escaping (Bool) -> Void) {
        menu.addItem(action(strings.text("on"), selected: value) { set(true) })
        menu.addItem(action(strings.text("off"), selected: !value) { set(false) })
    }
    private func reminderChoices(in menu: NSMenu, value: Int?, set: @escaping (Int) -> Void) {
        if value == nil { menu.addItem(label(strings.text("reminders.custom"))) }
        for minutes in [0, 15, 30, 45] {
            menu.addItem(action(minutes == 0 ? strings.text("off") : strings.text("minutesBefore", minutes), selected: value == minutes) { set(minutes) })
        }
    }
    private func rebuildMenu() {
        menu.removeAllItems()
        let panelItem = NSMenuItem()
        let panel = NSHostingView(rootView: PrayerPanel(model: model))
        panel.frame = NSRect(origin: .zero, size: panel.fittingSize)
        panel.autoresizingMask = [.width]
        panelItem.view = panel
        menu.addItem(panelItem)
        menu.addItem(.separator())
        let locationMenu = LocationMenu(level: .countries); locationMenu.delegate = self
        let locationItem = NSMenuItem(title: strings.text("location"), action: nil, keyEquivalent: ""); locationItem.submenu = locationMenu
        menu.addItem(locationItem)
        if !model.locationMatches.isEmpty {
            let matches = submenu(strings.text("location.match"), to: menu)
            for match in model.locationMatches {
                matches.addItem(action("\(match.label) · \(match.timeZoneIdentifier)") { [weak model] in model?.chooseMatch(match) })
            }
        }
        if model.pendingLocality != nil && !model.isResolving {
            menu.addItem(action(strings.text("location.retry")) { [weak model] in model?.retry() })
        }
        let calculation = submenu(strings.text("calculationMethod"), to: menu)
        calculation.addItem(action(strings.text("calculationMethod.diyanet"), selected: true) {})
        let asr = submenu(strings.text("asr"), to: menu)
        for value in AsrMethod.allCases {
            asr.addItem(action(strings.text("asr.\(value.rawValue)"), selected: model.preferences.asrMethod == value) { [weak model] in model?.update { $0.asrMethod = value } })
        }
        let language = submenu(strings.text("language"), to: menu)
        for value in AppLanguage.allCases {
            language.addItem(action(value == .system ? strings.text("system") : value.nativeName, selected: model.preferences.language == value) { [weak model] in model?.update { $0.language = value } })
        }
        let clock = submenu(strings.text("clockFormat"), to: menu)
        for value in ClockFormat.allCases {
            clock.addItem(action(strings.text(value == .system ? "system" : "clock.\(value.rawValue)"), selected: model.preferences.clockFormat == value) { [weak model] in model?.update { $0.clockFormat = value } })
        }
        let alerts = submenu(strings.text("notifications"), to: menu)
        boolChoices(in: alerts, value: model.preferences.startNotifications) { [weak model] value in model?.update { $0.startNotifications = value } }
        alerts.addItem(.separator()); alerts.addItem(label(strings.text(model.notificationStatusKey)))
        alerts.addItem(action(strings.text("notifications.settings")) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        })
        let reminders = submenu(strings.text("reminders"), to: menu)
        let shared = submenu(strings.text("reminders.all"), to: reminders)
        reminderChoices(in: shared, value: model.preferences.sharedReminder) { [weak model] value in model?.update { $0.setAllReminders(value) } }
        reminders.addItem(.separator())
        for prayer in Prayer.obligatory {
            let child = submenu(strings.name(prayer), to: reminders)
            reminderChoices(in: child, value: model.preferences.reminder(for: prayer)) { [weak model] value in model?.update { $0.reminders[prayer] = value } }
        }
        if model.preferences.developerMode {
            let tests = submenu(strings.text("notifications.test"), to: menu)
            tests.addItem(label(strings.text(model.notificationStatusKey)))
            if let failure = model.notificationTestFailureKey { tests.addItem(label(strings.text(failure))) }
            if !model.canSendTestNotification {
                tests.addItem(action(strings.text("notifications.settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                })
            }
            tests.addItem(.separator())
            for prayer in Prayer.obligatory {
                let child = submenu(strings.name(prayer), to: tests)
                for kind in NotificationTestKind.allCases {
                    let entry = action(kind.title(using: strings)) { [weak model] in model?.sendTestNotification(prayer: prayer, kind: kind) }
                    entry.isEnabled = model.canSendTestNotification
                    child.addItem(entry)
                }
            }
        }
        let login = submenu(strings.text("login"), to: menu)
        boolChoices(in: login, value: model.loginEnabled) { [weak model] enabled in model?.setLogin(enabled) }
        if model.loginRequiresApproval { login.addItem(action(strings.text("login.approval")) { SMAppService.openSystemSettingsLoginItems() }) }
        menu.addItem(.separator())
        menu.addItem(action(strings.text(model.failureKey == nil ? "refresh" : "retry"), key: "r") { [weak model] in model?.retry() })
        let theme = submenu(strings.text("theme"), to: menu)
        for value in Theme.allCases {
            theme.addItem(action(strings.text(value.rawValue), selected: model.preferences.theme == value) { [weak model] in model?.update { $0.theme = value } })
        }
        menu.addItem(.separator())
        let developer = submenu(strings.text("developerMode"), to: menu)
        boolChoices(in: developer, value: model.preferences.developerMode) { [weak model] enabled in model?.setDeveloperMode(enabled) }
        menu.addItem(action(strings.text("about")) { [weak self] in self?.showAbout() })
        menu.addItem(action(strings.text("quit"), key: "q") { NSApp.terminate(nil) })
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let locations = menu as? LocationMenu { loadLocations(locations) }
        else if menu === self.menu && !tracking { model.tick(); rebuildMenu() }
    }
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        tracking = true; model.tick(); model.refreshLoginStatus()
        model.syncNotifications(requestPermission: false)
        secondsTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.tick(); self?.updateStatus() }
        }
        secondsTimer = timer; RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .eventTracking)
    }
    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        tracking = false; secondsTimer?.invalidate(); secondsTimer = nil
        // Menu actions are dispatched after tracking finishes; rebuild on the next open.
        updateStatus()
    }
    func updateStatus() {
        let end = model.snapshot?.nextBoundary
        // Apply the threshold to the rounded badge, so it never displays 60m.
        let minutes = end.map { TimeDisplay.minutes(until: $0, now: model.now) }
        let title = minutes.flatMap { (1..<60).contains($0) ? " " + strings.text("minuteBadge", $0) : nil } ?? ""
        item.button?.title = title
        item.button?.toolTip = "MySalah · \(model.statusText)"
        let accessibilityParts = ["MySalah", model.snapshot?.nextPrayer.map { strings.name($0) } ?? "", title.trimmingCharacters(in: .whitespaces)]
        item.button?.setAccessibilityLabel(accessibilityParts.filter { !$0.isEmpty }.joined(separator: ", "))
        guard !tracking else { return }
        boundaryTimer?.invalidate()
        let remaining = end?.timeIntervalSince(model.now) ?? 60
        let untilChange = remaining > 0 ? max(0.1, remaining - Double(max(0, Int(ceil(remaining / 60)) - 1)) * 60 + 0.05) : 1
        let timer = Timer(timeInterval: min(60, untilChange), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.tick(); self?.updateStatus() }
        }
        boundaryTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    private func loadLocations(_ target: LocationMenu) {
        guard !target.loaded, !target.loading else { return }
        if let cached = catalogs[target.level.cacheKey] { populate(target, places: cached); return }
        target.loading = true; target.removeAllItems(); target.addItem(label(strings.text("location.loading")))
        let level = target.level
        Task { [weak self, weak target] in
            guard let self, let target else { return }
            let saved = await catalogCache.read(CachedPlaces.self, key: "places-\(level.cacheKey)")
            if let saved, Date().timeIntervalSince(saved.date) < 15 * 86_400 {
                catalogs[level.cacheKey] = saved.places; populate(target, places: saved.places); return
            }
            do {
                let places: [Place]
                switch level {
                case .countries: places = try await model.provider.countries()
                case .regions(let country): places = try await model.provider.regions(countryID: country.id)
                case .districts(_, let region): places = try await model.provider.districts(regionID: region.id)
                }
                catalogs[level.cacheKey] = places
                try? await catalogCache.write(CachedPlaces(date: Date(), places: places), key: "places-\(level.cacheKey)")
                populate(target, places: places)
            } catch {
                if let saved { catalogs[level.cacheKey] = saved.places; populate(target, places: saved.places) }
                else {
                    target.loading = false; target.removeAllItems()
                    target.addItem(action(strings.text("location.failed")) { [weak self, weak target] in if let target { self?.loadLocations(target) } })
                }
            }
        }
    }
    private func populate(_ target: LocationMenu, places: [Place]) {
        target.loading = false; target.loaded = true; target.removeAllItems()
        let current = model.preferences.location?.locality
        for place in places.sorted(by: { $0.displayName(language: strings.language).localizedStandardCompare($1.displayName(language: strings.language)) == .orderedAscending }) {
            let title = place.displayName(language: strings.language).localizedCapitalized
            let entry: NSMenuItem
            switch target.level {
            case .countries:
                entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let child = LocationMenu(level: .regions(place)); child.delegate = self; entry.submenu = child
                entry.state = current?.country.id == place.id ? .on : .off
            case .regions(let country):
                entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let child = LocationMenu(level: .districts(country, place)); child.delegate = self; entry.submenu = child
                entry.state = current?.country.id == country.id && current?.region.id == place.id ? .on : .off
            case .districts(let country, let region):
                let locality = Locality(country: country, region: region, district: place)
                entry = action(title, selected: current?.id == locality.id) { [weak model] in model?.select(locality) }
            }
            target.addItem(entry)
        }
        if places.isEmpty { target.addItem(label(strings.text("location.empty"))) }
    }
    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "MySalah 1.0"
        alert.informativeText = strings.text("about.description") + "\n\nMIT · © 2026 Mehmet"
        alert.addButton(withTitle: strings.text("ok"))
        alert.addButton(withTitle: strings.text("about.licenses"))
        alert.addButton(withTitle: strings.text("about.source"))
        let response = alert.runModal()
        if response == .alertSecondButtonReturn, let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") { NSWorkspace.shared.open(url) }
        if response == .alertThirdButtonReturn, let url = URL(string: "https://ezanvakti.emushaf.net/") { NSWorkspace.shared.open(url) }
    }
}
