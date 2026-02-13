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
            let className = String(describing: type(of: window))
            // MenuBarExtra uses _NSPopoverWindow or similar
            guard className.contains("Popover") || className.contains("MenuBarExtra") else { return }
            Task { @MainActor [weak self] in
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
            let className = String(describing: type(of: window))
            guard className.contains("Popover") || className.contains("MenuBarExtra") else { return }
            Task { @MainActor [weak self] in
                self?.isVisible = false
            }
        }
        observers.append(resignObserver)
    }
}
