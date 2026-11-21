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
    private var application: AXUIElement?
    private var processID: pid_t?
    private var recent: [AXUIElement: [AXUIElement]] = [:]

    func refresh(for pid: pid_t) {
        _ = snapshot(for: pid)
    }

    func switchBack(in pid: pid_t) {
        guard let window = snapshot(for: pid),
              let history = recent[window], history.count > 1 else { return }

        if AXUIElementPerformAction(history[1], kAXPressAction as CFString) == .success {
            // Read what Safari actually selected before updating history.
            refresh(for: pid)
        }
    }

    private func snapshot(for pid: pid_t) -> AXUIElement? {
        if processID != pid {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.2)
            application = element
            processID = pid
            recent.removeAll()
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

        let liveTabs = Set(tabs)
        let previous = (recent[window] ?? []).filter { $0 != selected && liveTabs.contains($0) }
        recent[window] = [selected] + previous
        return window
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
