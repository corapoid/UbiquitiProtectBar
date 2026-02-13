import SwiftUI
import AppKit

/// Tracks the visibility of the MenuBarExtra window via NSWindow notifications
@MainActor
final class MenuBarVisibilityTracker: ObservableObject {
    @Published private(set) var isVisible = false
    
    private var observers: [NSObjectProtocol] = []
    
    init() {
        setupObservers()
    }
    
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    private func setupObservers() {
        // Window becomes key (user opened the popover)
        let keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                guard Self.isMenuBarExtraWindow(window) else { return }
                self?.isVisible = true
            }
        }
        observers.append(keyObserver)
        
        // Window resigns key (user clicked away, popover closes)
        let resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                guard Self.isMenuBarExtraWindow(window) else { return }
                self?.isVisible = false
            }
        }
        observers.append(resignObserver)
    }
    
    /// Check if this is the MenuBarExtra panel window
    private static func isMenuBarExtraWindow(_ window: NSWindow) -> Bool {
        // MenuBarExtra creates an NSPanel with specific characteristics
        // It has styleMask with .nonactivatingPanel or is titled ""
        // The window class is typically _NSPopoverWindow or NSPanel
        let className = String(describing: type(of: window))
        return className.contains("Popover") ||
               className.contains("MenuBarExtra") ||
               (window is NSPanel && window.title.isEmpty && window.level == .popUpMenu)
    }
}
