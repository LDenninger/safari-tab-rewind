import AppKit
import Carbon
import SwiftUI

private final class SettingsState: ObservableObject {
    @Published var shortcut = Shortcut.standard
    @Published var showMenuBar = false
    @Published var startAtLogin = false
    @Published var accessibilityGranted = false
    @Published var recording = false
    @Published var shortcutUnavailable = false
}

final class SettingsWindow: NSWindow {
    private let settings = SettingsState()
    private let saveShortcut: (Shortcut) -> Bool

    init(saveShortcut: @escaping (Shortcut) -> Bool,
         setMenuBarVisibility: @escaping (Bool) -> Void,
         setStartAtLogin: @escaping (Bool) -> Void,
         openAccessibility: @escaping () -> Void) {
        self.saveShortcut = saveShortcut
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 315),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "TabRewind Settings"
        isReleasedWhenClosed = false
        contentViewController = NSHostingController(rootView: SettingsForm(
            settings: settings,
            recordShortcut: { [weak self] in self?.beginRecording() },
            restoreShortcut: { [weak self] in self?.assign(.standard) },
            setMenuBarVisibility: setMenuBarVisibility,
            setStartAtLogin: setStartAtLogin,
            openAccessibility: openAccessibility,
            done: { [weak self] in self?.close() }
        ))
    }

    func refresh(shortcut: Shortcut, showMenuBar: Bool, startAtLogin: Bool, accessibilityGranted: Bool) {
        settings.shortcut = shortcut
        settings.showMenuBar = showMenuBar
        settings.startAtLogin = startAtLogin
        if settings.accessibilityGranted != accessibilityGranted {
            settings.accessibilityGranted = accessibilityGranted
            let height: CGFloat = accessibilityGranted ? 249 : 315
            let frameHeight = frameRect(forContentRect: NSRect(x: 0, y: 0, width: 460, height: height)).height
            var newFrame = frame
            newFrame.origin.y += newFrame.height - frameHeight
            newFrame.size.height = frameHeight
            setFrame(newFrame, display: isVisible)
        }
    }

    override func sendEvent(_ event: NSEvent) {
        guard settings.recording, event.type == .keyDown else {
            super.sendEvent(event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape), event.modifierFlags.intersection([.control, .option, .shift, .command]).isEmpty {
            endRecording()
        } else if !event.isARepeat, let shortcut = Shortcut(event: event) {
            assign(shortcut)
        }
    }

    override func resignKey() {
        endRecording()
        super.resignKey()
    }

    private func beginRecording() {
        settings.shortcutUnavailable = false
        settings.recording = true
    }

    private func endRecording() {
        settings.recording = false
        settings.shortcutUnavailable = false
    }

    private func assign(_ shortcut: Shortcut) {
        if saveShortcut(shortcut) {
            settings.shortcut = shortcut
            endRecording()
        } else {
            settings.shortcutUnavailable = true
        }
    }
}

private struct SettingsForm: View {
    @ObservedObject var settings: SettingsState
    let recordShortcut: () -> Void
    let restoreShortcut: () -> Void
    let setMenuBarVisibility: (Bool) -> Void
    let setStartAtLogin: (Bool) -> Void
    let openAccessibility: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Switch Safari tabs") {
                        Button(action: recordShortcut) {
                            Text(settings.recording ? "Press shortcut" : settings.shortcut.label)
                                .monospaced()
                                .frame(minWidth: 87)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .accessibilityLabel("Switch Safari tabs shortcut")
                        .accessibilityValue(settings.recording ? "Recording" : settings.shortcut.label)
                        .accessibilityHint("Activate to enter a new key combination")
                    }
                } header: {
                    Text("Keyboard Shortcut")
                } footer: {
                    HStack {
                        Text(shortcutHint)
                            .foregroundStyle(settings.shortcutUnavailable ? Color.red : Color.secondary)
                        Spacer()
                        Button("Restore Default", action: restoreShortcut)
                            .disabled(settings.shortcut == .standard && !settings.recording)
                    }
                }

                Section("General") {
                    Toggle("Show in Menu Bar", isOn: Binding(
                        get: { settings.showMenuBar }, set: setMenuBarVisibility
                    ))
                    Toggle("Start at Login", isOn: Binding(
                        get: { settings.startAtLogin }, set: setStartAtLogin
                    ))
                }

                if !settings.accessibilityGranted {
                    Section("Accessibility") {
                        LabeledContent("Allow Safari tab switching") {
                            Button("Open System Settings…", action: openAccessibility)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Quit TabRewind") { NSApp.terminate(nil) }
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 460, minHeight: settings.accessibilityGranted ? 249 : 315)
    }

    private var shortcutHint: String {
        if settings.shortcutUnavailable { return "Shortcut unavailable. Try another." }
        if settings.recording { return "Press a key combination. Esc cancels." }
        return "Click the shortcut to change it."
    }
}
