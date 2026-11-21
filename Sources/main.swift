import AppKit
import ApplicationServices
import Carbon
import ServiceManagement

private let safariBundleID = "com.apple.Safari"

struct Shortcut: Equatable {
    let key: UInt32
    let modifiers: UInt32
    let label: String

    static let standard = Shortcut(key: UInt32(kVK_Tab), modifiers: UInt32(controlKey), label: "⌃⇥")
    private static let modifierKeys: [(NSEvent.ModifierFlags, Int, String)] = [
        (.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
        (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")
    ]

    var modifierFlags: NSEvent.ModifierFlags {
        Self.modifierKeys.reduce(into: []) { flags, key in
            if modifiers & UInt32(key.1) != 0 { flags.insert(key.0) }
        }
    }

    init(key: UInt32, modifiers: UInt32, label: String) {
        self.key = key
        self.modifiers = modifiers
        self.label = label
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !flags.intersection([.control, .option, .command]).isEmpty,
              let characters = event.charactersIgnoringModifiers,
              let character = characters.first else { return nil }

        let namedKeys: [UInt16: String] = [
            UInt16(kVK_Tab): "⇥", UInt16(kVK_Space): "Space",
            UInt16(kVK_Return): "↩", UInt16(kVK_Delete): "⌫",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓"
        ]
        let keyLabel: String
        if let name = namedKeys[event.keyCode] {
            keyLabel = name
        } else if character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol {
            keyLabel = String(character).uppercased()
        } else {
            return nil
        }

        let active = Self.modifierKeys.filter { flags.contains($0.0) }
        key = UInt32(event.keyCode)
        modifiers = active.reduce(0) { $0 | UInt32($1.1) }
        label = active.map { $0.2 }.joined() + keyLabel
    }

    static func load() -> Shortcut {
        guard let settings = UserDefaults.standard.dictionary(forKey: "shortcut"),
              let key = settings["key"] as? UInt32,
              let modifiers = settings["modifiers"] as? UInt32,
              let label = settings["label"] as? String else { return .standard }
        return Shortcut(key: key, modifiers: modifiers, label: label)
    }

    func save() {
        UserDefaults.standard.set(["key": key, "modifiers": modifiers, "label": label], forKey: "shortcut")
    }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let tabs = SafariTabs()
    private var shortcut = Shortcut.load()
    private var hotKey: EventHotKeyRef?
    private var keyHeld = false
    private var handler: EventHandlerRef?
    private var timer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var modifierMonitor: Any?
    private var statusItem: NSStatusItem!
    private var permissionItem: NSMenuItem!
    private var shortcutItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var settingsWindow: SettingsWindow?
    private var hotKeyError: OSStatus?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, info in
            guard let event, let info else { return OSStatus(eventNotHandledErr) }
            return Unmanaged<App>.fromOpaque(info).takeUnretainedValue().handleHotKey(event)
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if result != noErr { shortcutItem.toolTip = "Couldn’t start the shortcut handler." }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.update() }

        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.update()
        }
        update()

        if !AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey: "requestedAccessibility") {
            UserDefaults.standard.set(true, forKey: "requestedAccessibility")
            requestAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshSettings()
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        let icon = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "TabRewind")
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "TabRewind"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        permissionItem = menu.addItem(withTitle: "Grant Accessibility…", action: #selector(openAccessibility), keyEquivalent: "")
        permissionItem.target = self
        shortcutItem = menu.addItem(withTitle: "", action: #selector(openSettings), keyEquivalent: "")
        shortcutItem.target = self
        let resetItem = menu.addItem(withTitle: "Reset Shortcut", action: #selector(resetShortcut), keyEquivalent: "")
        resetItem.target = self
        loginItem = menu.addItem(withTitle: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit TabRewind", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = NSApp
        statusItem.menu = menu
        menuWillOpen(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        permissionItem.isHidden = AXIsProcessTrusted()
        shortcutItem.title = "Settings (\(shortcut.label))…"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private var activeSafariPID: pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == safariBundleID else { return nil }
        return app.processIdentifier
    }

    private func update() {
        guard let pid = activeSafariPID, AXIsProcessTrusted() else {
            unregister()
            hotKeyError = nil
            return
        }
        if handler != nil, hotKey == nil, hotKeyError == nil {
            hotKeyError = register(shortcut)
            shortcutItem.toolTip = hotKeyError == nil ? nil : "This shortcut is unavailable. Choose another."
            if hotKey != nil {
                modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                    self?.finishCycleIfReleased(event.modifierFlags)
                }
            }
        }
        finishCycleIfReleased(NSEvent.modifierFlags)
        tabs.refresh(for: pid)
    }

    private func finishCycleIfReleased(_ flags: NSEvent.ModifierFlags) {
        if !flags.contains(shortcut.modifierFlags) { tabs.finishCycle() }
    }

    private func register(_ value: Shortcut) -> OSStatus? {
        let id = EventHotKeyID(signature: 0x53545243, id: 1)
        let result = RegisterEventHotKey(value.key, value.modifiers, id, GetApplicationEventTarget(),
                                         UInt32(kEventHotKeyExclusive), &hotKey)
        return result == noErr ? nil : result
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let modifierMonitor {
            NSEvent.removeMonitor(modifierMonitor)
            self.modifierMonitor = nil
        }
        tabs.finishCycle()
        keyHeld = false
    }

    private func handleHotKey(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                EventParamType(typeEventHotKeyID), nil,
                                MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
              id.signature == 0x53545243, id.id == 1 else { return OSStatus(eventNotHandledErr) }
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
            keyHeld = false
        } else if !keyHeld, let pid = activeSafariPID {
            keyHeld = true
            tabs.advance(in: pid)
        }
        return noErr
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = SettingsWindow(
                saveShortcut: { [weak self] in self?.apply($0) ?? false },
                setMenuBarVisibility: { [weak self] in self?.setMenuBarVisibility($0) },
                setStartAtLogin: { [weak self] in self?.setStartAtLogin($0) },
                openAccessibility: { [weak self] in self?.openAccessibility() }
            )
            window.delegate = self
            settingsWindow = window
            refreshSettings()
            window.center()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshSettings() {
        settingsWindow?.refresh(
            shortcut: shortcut,
            showMenuBar: statusItem.isVisible,
            startAtLogin: SMAppService.mainApp.status == .enabled,
            accessibilityGranted: AXIsProcessTrusted()
        )
    }

    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
        update()
    }

    @objc private func resetShortcut() {
        if !apply(.standard) {
            showMessage("Shortcut unavailable", detail: "macOS rejected the default shortcut.")
        }
    }

    private func setMenuBarVisibility(_ visible: Bool) {
        statusItem.isVisible = visible
        UserDefaults.standard.set(visible, forKey: "showMenuBarIcon")
        refreshSettings()
    }

    private func apply(_ candidate: Shortcut) -> Bool {
        unregister()
        let registered = register(candidate) == nil
        if registered {
            shortcut = candidate
            shortcut.save()
        }
        unregister()
        hotKeyError = nil
        refreshSettings()
        update()
        return registered
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @objc private func openAccessibility() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        setStartAtLogin(SMAppService.mainApp.status != .enabled)
    }

    private func setStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showMessage("Couldn’t change Start at Login", detail: error.localizedDescription)
        }
        refreshSettings()
        update()
    }

    private func showMessage(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let application = NSApplication.shared
let delegate = App()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
