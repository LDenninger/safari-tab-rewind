import ApplicationServices

private extension AXUIElement {
    func attribute(_ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    var children: [AXUIElement] {
        attribute(kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    var identifier: String {
        attribute(kAXIdentifierAttribute) as? String ?? ""
    }
}

final class SafariTabs {
    private struct Snapshot {
        let window: AXUIElement
        let selected: AXUIElement
        let tabs: [AXUIElement]
    }

    private struct Cycle {
        let window: AXUIElement
        let order: [AXUIElement]
        var index = 0

        var selected: AXUIElement { order[index] }
    }

    private var application: AXUIElement?
    private var processID: pid_t?
    private var recent: [AXUIElement: [AXUIElement]] = [:]
    private var cycle: Cycle?

    func refresh(for pid: pid_t) {
        if let state = snapshot(for: pid) {
            observe(state)
        }
    }

    func advance(in pid: pid_t) {
        guard let state = snapshot(for: pid) else { return }
        observe(state)
        let history = recent[state.window] ?? [state.selected]
        let visited = Set(history)
        // Keep the starting order fixed until the modifiers are released.
        var active = cycle ?? Cycle(window: state.window,
                                    order: history + state.tabs.filter { !visited.contains($0) })
        let live = Set(state.tabs)
        for offset in 1..<active.order.count {
            let index = (active.index + offset) % active.order.count
            let tab = active.order[index]
            guard live.contains(tab) else { continue }
            if AXUIElementPerformAction(tab, kAXPressAction as CFString) == .success {
                active.index = index
                cycle = active
            }
            return
        }
    }

    func finishCycle() {
        guard let active = cycle else { return }
        cycle = nil
        if let history = recent[active.window] {
            recent[active.window] = [active.selected] + history.filter { $0 != active.selected }
        }
    }

    private func observe(_ state: Snapshot) {
        if let active = cycle {
            if active.window == state.window && active.selected == state.selected { return }
            finishCycle()
        }
        let live = Set(state.tabs)
        let previous = (recent[state.window] ?? []).filter { $0 != state.selected && live.contains($0) }
        recent[state.window] = [state.selected] + previous
    }

    private func snapshot(for pid: pid_t) -> Snapshot? {
        if processID != pid {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.2)
            application = element
            processID = pid
            recent.removeAll()
            cycle = nil
        }

        guard let application else { return nil }
        let openWindows = application.attribute(kAXWindowsAttribute) as? [AXUIElement]
        if let openWindows {
            let liveWindows = Set(openWindows)
            recent = recent.filter { liveWindows.contains($0.key) }
        }

        guard let focused = application.attribute(kAXFocusedWindowAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let window = focused as! AXUIElement
        guard let bar = tabBar(in: window, depth: 2) else { return nil }
        let tabs = bar.children.filter { $0.identifier.hasPrefix("TabBarTab?") }
        guard let selected = tabs.first(where: {
            ($0.attribute(kAXValueAttribute) as? NSNumber)?.boolValue == true
        }) else { return nil }

        return Snapshot(window: window, selected: selected, tabs: tabs)
    }

    private func tabBar(in element: AXUIElement, depth: Int) -> AXUIElement? {
        let children = element.children
        if let bar = children.first(where: { $0.identifier.hasPrefix("TabBar?") }) {
            return bar
        }
        guard depth > 0 else { return nil }
        for child in children {
            let role = child.attribute(kAXRoleAttribute) as? String
            // Skip the tab's page view and the browser toolbar.
            guard role == "AXGroup" || role == "AXSplitGroup" else { continue }
            if let bar = tabBar(in: child, depth: depth - 1) {
                return bar
            }
        }
        return nil
    }
}
