import SwiftUI

@main
struct SpotifyControllerApp: App {
    @StateObject private var playback = PlaybackViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playback)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 360, height: 400)
    }
}
