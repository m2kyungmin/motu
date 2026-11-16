import SwiftUI

@main
struct CcutuApp: App {
    @State private var coordinator = SessionCoordinator()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environment(coordinator)
        }
        .onChange(of: phase) { _, p in
            if p == .active { SoundPlayer.shared.resumeBGM() }
            if p == .background { SoundPlayer.shared.pauseForBackground() }
        }
    }
}
