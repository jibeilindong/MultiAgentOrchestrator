import AppKit
import SwiftUI

@MainActor
final class QuickChatWindowManager: NSObject, NSWindowDelegate {
    static let shared = QuickChatWindowManager()

    private weak var window: NSWindow?
    private weak var store: QuickChatStore?
    private weak var appState: AppState?

    func syncPresentation(store: QuickChatStore, appState: AppState) {
        self.store = store
        self.appState = appState

        if store.isPresented {
            presentWindow(store: store, appState: appState)
        } else {
            closeWindow()
        }
    }

    private func presentWindow(store: QuickChatStore, appState: AppState) {
        let window = window ?? makeWindow(store: store, appState: appState)
        updateWindowContent(window, store: store, appState: appState)
        if !window.isVisible {
            window.center()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeWindow() {
        guard let window else { return }
        window.orderOut(nil)
        window.close()
        self.window = nil
    }

    private func makeWindow(store: QuickChatStore, appState: AppState) -> NSWindow {
        let controller = NSHostingController(rootView: AnyView(QuickChatModalView(store: store).environmentObject(appState)))
        let window = NSWindow(contentViewController: controller)
        window.delegate = self
        window.title = "Quick Chat"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.minSize = NSSize(width: 980, height: 680)
        window.setFrame(NSRect(x: 0, y: 0, width: 1180, height: 780), display: true)
        window.setFrameAutosaveName("QuickChatWindow")
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        self.window = window
        return window
    }

    private func updateWindowContent(_ window: NSWindow, store: QuickChatStore, appState: AppState) {
        let rootView = AnyView(
            QuickChatModalView(store: store)
                .environmentObject(appState)
        )

        if let controller = window.contentViewController as? NSHostingController<AnyView> {
            controller.rootView = rootView
        } else {
            window.contentViewController = NSHostingController(rootView: rootView)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let store, let appState else { return }
        self.window = nil
        if store.isPresented {
            store.handleDismiss(using: appState)
        }
    }
}

struct QuickChatWindowBridge: NSViewRepresentable {
    @ObservedObject var store: QuickChatStore
    let appState: AppState

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            QuickChatWindowManager.shared.syncPresentation(store: store, appState: appState)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            QuickChatWindowManager.shared.syncPresentation(store: store, appState: appState)
        }
    }
}
