import AppKit
import Combine
import SwiftUI

@MainActor
final class PlaybackViewModel: ObservableObject {
    let artist = "Khruangbin"
    let song = "Time (You and I)"
    let album = "Mordechai"
    let albumYear = 2020
    let duration: TimeInterval = 338

    @Published var isPlaying = true
    @Published var isLiked = false
    @Published var progress: TimeInterval = 142
    @Published var coverImage: NSImage?
    @Published var showSettings = false

    private var timer: AnyCancellable?

    init() {
        coverImage = CoverImageLoader.load()
        startTickerIfNeeded()
    }

    var albumSubtitle: String {
        "\(album) (\(albumYear))"
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, progress / duration))
    }

    func togglePlayPause() {
        isPlaying.toggle()
        startTickerIfNeeded()
    }

    func toggleLike() {
        isLiked.toggle()
    }

    func skipBackward() {
        progress = max(0, progress - 15)
    }

    func skipForward() {
        progress = min(duration, progress + 15)
    }

    func seek(fraction: Double) {
        progress = duration * min(1, max(0, fraction))
    }

    private func startTickerIfNeeded() {
        timer?.cancel()
        guard isPlaying else { return }

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if progress < duration {
                    progress += 1
                } else {
                    progress = 0
                }
            }
    }
}

private final class ResourceBundleAnchor {}

enum CoverImageLoader {
    static func load() -> NSImage? {
        if let url = resourceBundle.url(forResource: "cover", withExtension: "jpg"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        let fileManager = FileManager.default
        let cwd = fileManager.currentDirectoryPath
        let executable = Bundle.main.bundleURL.deletingLastPathComponent().path

        let candidates = [
            "\(cwd)/cover.jpg",
            "\(cwd)/../cover.jpg",
            "\(executable)/cover.jpg",
            "\(executable)/../cover.jpg",
            "\(executable)/../../cover.jpg",
        ]

        for path in candidates {
            if fileManager.fileExists(atPath: path), let image = NSImage(contentsOfFile: path) {
                return image
            }
        }

        return nil
    }

    private static var resourceBundle: Bundle {
        let spmBundleName = "SpotifyController_SpotifyController.bundle"
        let searchRoots = [
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
            URL(fileURLWithPath: Bundle(for: ResourceBundleAnchor.self).bundlePath).deletingLastPathComponent(),
        ]

        for root in searchRoots {
            let url = root.appendingPathComponent(spmBundleName)
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        return Bundle(for: ResourceBundleAnchor.self)
    }
}
