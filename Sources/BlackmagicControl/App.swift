import SwiftUI
import AppKit

/// App-wide constants. Keep `version` in sync with `Packaging/bundle.sh`
/// (CFBundleShortVersionString) so the top-bar label matches the bundle.
enum AppInfo {
    static let version = "3.7"
    static let author = "w.dauel"
}

@main
struct BlackmagicControlApp: App {
    @StateObject private var manager = CameraManager()

    init() {
        // When run as an unbundled SwiftPM executable, force a normal (Dock +
        // foreground) app so the window actually comes forward.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        Window("Blackmagic Camera Control", id: "main") {
            RootView()
                .environmentObject(manager)
                .frame(minWidth: 940, minHeight: 680)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
