import AppKit
import Combine
import SwiftUI

@MainActor
final class PlaybackViewModel: ObservableObject {

    // MARK: - Track info

    @Published var artist = ""
    @Published var song = ""
    @Published var album = ""
    @Published var albumYear = 0
    @Published var duration: TimeInterval = 0

    // MARK: - Playback state

    @Published var isPlaying = false
    @Published var isLiked = false
    @Published var progress: TimeInterval = 0

    // MARK: - UI state

    @Published var coverImage: NSImage?
    @Published var isSpotifyRunning = false
    // Incremented on like/unlike failure — views bind ShakeEffect to this value.
    @Published var likeShakeCount = 0

    // MARK: - Private

    private let bridge = SpotifyBridge()
    private let likeService = SpotifyLikeService()
    private let logger = SongLogger()
    let authService = SpotifyAuthService()

    private(set) var currentTrackId = ""

    // Increments whenever the user clicks the heart button. A background
    // fetchLikeStatus task captures this value when it starts, and refuses to
    // overwrite `isLiked` if the counter has moved (i.e. the user clicked since).
    // Without this, slow web responses can clobber recent user clicks.
    private var likeActionVersion = 0

    private var displayTimer: AnyCancellable?
    private var positionSyncTimer: AnyCancellable?
    private var authServiceCancellable: AnyCancellable?
    private var loggingCancellable: AnyCancellable?

    private var artworkRequestID = 0
    private var loadedArtworkURL = ""
    // Guards against fetching like status twice for the same track.
    private var likeStatusFetched = false

    // MARK: - Init

    init() {
        likeService.authService = authService
        wireBridge()
        // Forward authService and logging changes so views observing this model update too.
        authServiceCancellable = authService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        loggingCancellable = LoggingSettings.shared.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        isSpotifyRunning = bridge.isRunning()
        if isSpotifyRunning {
            bridge.queryCurrentState()
        }
        startDisplayTimer()
        startPositionSyncTimer()
    }

    // MARK: - Computed

    var albumSubtitle: String {
        albumYear > 0 ? "\(album) (\(albumYear))" : album
    }

    var isLikeAvailable: Bool {
        (authService.oauthEnabled && authService.isConnected) || LoggingSettings.shared.loggingEnabled
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, progress / duration))
    }

    // MARK: - Commands

    func togglePlayPause() {
        if isPlaying {
            bridge.pause()
            isPlaying = false
        } else {
            bridge.play()
            isPlaying = true
        }
    }

    func skipBackward() { bridge.previousTrack() }
    func skipForward()  { bridge.nextTrack() }

    func seek(fraction: Double) {
        let target = duration * min(1, max(0, fraction))
        progress = target
        bridge.seek(to: target)
    }

    func toggleLike() {
        guard !currentTrackId.isEmpty else { return }
        let oauthAvail = authService.oauthEnabled && authService.isConnected
        let loggingAvail = LoggingSettings.shared.loggingEnabled
        guard oauthAvail || loggingAvail else { return }

        let wantLiked = !isLiked
        isLiked = wantLiked
        likeActionVersion += 1
        let myVersion = likeActionVersion

        if loggingAvail {
            logger.logLikeToggled(
                track: song, artist: artist, trackId: currentTrackId,
                action: wantLiked ? "liked" : "unliked"
            )
        }

        guard oauthAvail else { return }
        let trackId = currentTrackId
        Task { [weak self] in
            guard let self else { return }
            let actual = await likeService.setLike(trackId: trackId, wantLiked: wantLiked)
            guard self.likeActionVersion == myVersion else { return }
            if let actual = actual {
                self.isLiked = actual
            } else {
                self.isLiked = !wantLiked  // revert optimistic update on failure
                self.likeShakeCount += 1
            }
        }
    }

    func launchSpotify() { bridge.launchSpotify() }

    func openInSpotify() {
        guard !currentTrackId.isEmpty,
              let url = URL(string: "spotify:track:\(currentTrackId)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func wireBridge() {
        bridge.onRunningChanged = { [weak self] running in
            self?.isSpotifyRunning = running
            if !running { self?.resetToIdle() }
        }
        bridge.onTrackChanged = { [weak self] info in
            self?.applyTrackInfo(info)
        }
        bridge.onStateChanged = { [weak self] state in
            self?.applyPlayerState(state)
        }
    }

    private func applyTrackInfo(_ info: SpotifyTrackInfo) {
        if info.albumYear > 0 { albumYear = info.albumYear }
        if info.duration  > 0 { duration  = info.duration  }

        // Can't determine track identity without a name; leave text fields as-is.
        guard !info.name.isEmpty else { return }

        let trackChanged = info.name != song || info.artist != artist

        song   = info.name
        artist = info.artist
        album  = info.album

        var shouldLogAfterFetch = false
        if trackChanged {
            currentTrackId    = info.trackId
            isLiked           = false
            likeStatusFetched = false
            loadedArtworkURL  = info.artworkURL
            coverImage        = nil
            startArtworkFetch(cdnURL: info.artworkURL, artist: info.artist, track: info.name)
            if LoggingSettings.shared.loggingEnabled {
                let oauthAvail = authService.oauthEnabled && authService.isConnected
                if oauthAvail {
                    // Defer logging until fetchLikeStatus resolves so we can include liked status.
                    shouldLogAfterFetch = true
                } else {
                    logger.logSongChanged(
                        track: info.name, artist: info.artist, album: info.album,
                        trackId: info.trackId, durationS: Int(info.duration), liked: nil
                    )
                }
            }
        } else {
            if !info.trackId.isEmpty && currentTrackId.isEmpty {
                currentTrackId = info.trackId
            }
            let urlChanged = !info.artworkURL.isEmpty && info.artworkURL != loadedArtworkURL
            if urlChanged {
                loadedArtworkURL = info.artworkURL
                startArtworkFetch(cdnURL: info.artworkURL, artist: info.artist, track: info.name)
            }
        }

        if !currentTrackId.isEmpty && !likeStatusFetched {
            likeStatusFetched = true
            fetchLikeStatus(trackId: currentTrackId, logOnComplete: shouldLogAfterFetch)
        }
    }

    private func fetchLikeStatus(trackId: String, logOnComplete: Bool = false) {
        guard !trackId.isEmpty else { return }
        let versionAtStart = likeActionVersion
        Task { [weak self] in
            guard let self else { return }
            let liked = await likeService.fetchLikedStatus(trackId: trackId)
            guard self.currentTrackId == trackId else { return }
            if self.likeActionVersion == versionAtStart {
                if let liked { self.isLiked = liked }
            }
            if logOnComplete {
                self.logger.logSongChanged(
                    track: self.song, artist: self.artist, album: self.album,
                    trackId: trackId, durationS: Int(self.duration), liked: liked
                )
            }
        }
    }

    private func startArtworkFetch(cdnURL: String, artist: String, track: String) {
        artworkRequestID += 1
        let id = artworkRequestID

        Task { [weak self] in
            guard let self else { return }
            var data: Data?

            if !cdnURL.isEmpty {
                data = await bridge.downloadArtwork(from: cdnURL)
            }

            if data == nil {
                data = await bridge.searchITunesArtwork(artist: artist, track: track)
            }

            guard self.artworkRequestID == id else { return }
            self.coverImage = data.flatMap { NSImage(data: $0) }
        }
    }

    private func applyPlayerState(_ state: SpotifyPlayerState) {
        switch state {
        case .playing(let position):
            isPlaying = true
            progress  = position
        case .paused(let position):
            isPlaying = false
            progress  = position
        case .stopped:
            isPlaying = false
            progress  = 0
        }
    }

    private func resetToIdle() {
        song              = ""
        artist            = ""
        album             = ""
        albumYear         = 0
        duration          = 0
        progress          = 0
        isPlaying         = false
        isLiked           = false
        likeStatusFetched = false
        coverImage        = nil
        loadedArtworkURL  = ""
        currentTrackId    = ""
    }

    private func startDisplayTimer() {
        displayTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, isPlaying else { return }
                if duration <= 0 || progress < duration {
                    progress += 1
                } else {
                    progress = 0
                }
            }
    }

    private func startPositionSyncTimer() {
        positionSyncTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, isSpotifyRunning, isPlaying else { return }
                Task { [weak self] in
                    guard let self else { return }
                    if let pos = await bridge.queryPosition() {
                        self.progress = pos
                    }
                }
            }
    }
}
