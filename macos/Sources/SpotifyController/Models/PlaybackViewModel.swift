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

    // MARK: - Private

    private let bridge = SpotifyBridge()
    private let likeService = SpotifyLikeService()
    let authService = SpotifyAuthService()

    private var currentTrackId = ""

    // Increments whenever the user clicks the heart button. A background
    // fetchLikeStatus task captures this value when it starts, and refuses to
    // overwrite `isLiked` if the counter has moved (i.e. the user clicked since).
    // Without this, slow web responses can clobber recent user clicks.
    private var likeActionVersion = 0

    private var displayTimer: AnyCancellable?
    private var positionSyncTimer: AnyCancellable?
    private var authServiceCancellable: AnyCancellable?

    private var reportedPosition: TimeInterval = 0
    private var reportedAt = Date()

    private var artworkRequestID = 0
    private var loadedArtworkURL = ""
    // Guards against fetching like status twice for the same track.
    private var likeStatusFetched = false

    // MARK: - Init

    init() {
        likeService.authService = authService
        wireBridge()
        // Forward authService changes so views observing this model update too.
        authServiceCancellable = authService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        isSpotifyRunning = bridge.isRunning()
        if isSpotifyRunning {
            bridge.queryCurrentState()
            // Belt-and-suspenders: if the first AppleScript query returned incomplete
            // track info (Spotify occasionally needs a moment to surface metadata),
            // retry once after a short delay. No-op when duration is already set.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, self.isSpotifyRunning, self.duration == 0 else { return }
                self.bridge.queryCurrentState()
            }
        }
        startDisplayTimer()
        startPositionSyncTimer()
    }

    // MARK: - Computed

    var albumSubtitle: String {
        albumYear > 0 ? "\(album) (\(albumYear))" : album
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, progress / duration))
    }

    // MARK: - Commands

    func togglePlayPause() {
        if isPlaying {
            bridge.pause()
            reportedPosition = progress
            isPlaying = false
        } else {
            bridge.play()
            reportedAt = Date()
            isPlaying = true
        }
    }

    func skipBackward() { bridge.previousTrack() }
    func skipForward()  { bridge.nextTrack() }

    func seek(fraction: Double) {
        let target = duration * min(1, max(0, fraction))
        progress         = target
        reportedPosition = target
        reportedAt       = Date()
        bridge.seek(to: target)
    }

    func toggleLike() {
        guard !currentTrackId.isEmpty else { return }
        guard authService.oauthEnabled && authService.isConnected else { return }
        let wantLiked = !isLiked
        isLiked = wantLiked
        likeActionVersion += 1
        let myVersion = likeActionVersion

        let trackId = currentTrackId
        Task { [weak self] in
            guard let self else { return }
            let actual = await likeService.setLike(trackId: trackId, wantLiked: wantLiked)
            guard self.likeActionVersion == myVersion else { return }
            if let actual = actual {
                self.isLiked = actual
            } else {
                self.isLiked = !wantLiked  // revert optimistic update on failure
            }
        }
    }

    func launchSpotify() { bridge.launchSpotify() }

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
        // Always update numeric fields. This runs even when the AppleScript try-block
        // fails and returns an empty name — it ensures `duration` is set so the timer
        // can fire and `progressFraction` is non-zero.
        if info.albumYear > 0 { albumYear = info.albumYear }
        if info.duration  > 0 { duration  = info.duration  }

        // Can't determine track identity without a name; leave text fields as-is.
        guard !info.name.isEmpty else { return }

        let trackChanged = info.name != song || info.artist != artist

        song   = info.name
        artist = info.artist
        album  = info.album

        if trackChanged {
            currentTrackId    = info.trackId
            isLiked           = false
            likeStatusFetched = false
            loadedArtworkURL  = info.artworkURL
            coverImage        = nil
            startArtworkFetch(cdnURL: info.artworkURL, artist: info.artist, track: info.name)
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
            fetchLikeStatus(trackId: currentTrackId)
        }
    }

    private func fetchLikeStatus(trackId: String) {
        guard !trackId.isEmpty else { return }
        let versionAtStart = likeActionVersion
        Task { [weak self] in
            guard let self else { return }
            guard let liked = await likeService.fetchLikedStatus(trackId: trackId) else { return }
            guard self.currentTrackId == trackId else { return }
            if self.likeActionVersion == versionAtStart {
                self.isLiked = liked
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
            isPlaying        = true
            progress         = position  // set immediately so the scrubber is correct before the timer fires
            reportedPosition = position
            reportedAt       = Date()
        case .paused(let position):
            isPlaying        = false
            progress         = position
            reportedPosition = position
        case .stopped:
            isPlaying        = false
            progress         = 0
            reportedPosition = 0
        }
    }

    private func resetToIdle() {
        song              = ""
        artist            = ""
        album             = ""
        albumYear         = 0
        duration          = 0
        progress          = 0
        reportedPosition  = 0
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
                guard let self, isPlaying, duration > 0 else { return }
                let elapsed = Date().timeIntervalSince(reportedAt)
                progress = min(duration, reportedPosition + elapsed)
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
                        reportedPosition = pos
                        reportedAt       = Date()
                    }
                }
            }
    }
}
