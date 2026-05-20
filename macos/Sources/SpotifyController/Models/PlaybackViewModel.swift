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
    @Published var showSettings = false
    @Published var isSpotifyRunning = false

    // MARK: - Private

    private let bridge = SpotifyBridge()

    private var displayTimer: AnyCancellable?
    private var positionSyncTimer: AnyCancellable?

    // The position Spotify last reported and the wall-clock moment of that report.
    // The display timer advances `progress` locally from this anchor.
    private var reportedPosition: TimeInterval = 0
    private var reportedAt = Date()

    // Artwork fetch de-duplication: only the most recent request ID wins.
    private var artworkRequestID = 0
    // URL that was used for the last completed artwork download.
    private var loadedArtworkURL = ""

    // MARK: - Init

    init() {
        wireBridge()
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
        // Placeholder — will be wired to spotify_liked.py approach in a later phase.
        isLiked.toggle()
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
        let trackChanged = info.name != song || info.artist != artist

        song   = info.name
        artist = info.artist
        album  = info.album
        if info.albumYear > 0 { albumYear = info.albumYear }
        if info.duration  > 0 { duration  = info.duration  }

        // Decide whether to (re)fetch artwork:
        // • Track changed → always reset and fetch (previous art no longer relevant).
        // • Same track, new CDN URL arrived → start a faster CDN download.
        // • Same track, same URL (or both empty) → nothing to do.
        let urlChanged = !info.artworkURL.isEmpty && info.artworkURL != loadedArtworkURL

        if trackChanged {
            loadedArtworkURL = info.artworkURL
            coverImage = nil
            startArtworkFetch(cdnURL: info.artworkURL, artist: info.artist, track: info.name)
        } else if urlChanged {
            loadedArtworkURL = info.artworkURL
            startArtworkFetch(cdnURL: info.artworkURL, artist: info.artist, track: info.name)
        }
    }

    private func startArtworkFetch(cdnURL: String, artist: String, track: String) {
        artworkRequestID += 1
        let id = artworkRequestID

        Task { [weak self] in
            guard let self else { return }

            // Primary: Spotify CDN URL (from AppleScript `artwork url of current track`).
            var data: Data?
            if !cdnURL.isEmpty {
                data = await bridge.downloadArtwork(from: cdnURL)
            }

            // Fallback: iTunes Search API — works for virtually all mainstream music,
            // no API key required. Covers the case where Spotify's AS returns no URL.
            if data == nil {
                data = await bridge.searchITunesArtwork(artist: artist, track: track)
            }

            // Discard if a newer request superseded this one.
            guard self.artworkRequestID == id else { return }
            self.coverImage = data.flatMap { NSImage(data: $0) }
        }
    }

    private func applyPlayerState(_ state: SpotifyPlayerState) {
        switch state {
        case .playing(let position):
            isPlaying        = true
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
        song             = ""
        artist           = ""
        album            = ""
        albumYear        = 0
        duration         = 0
        progress         = 0
        reportedPosition = 0
        isPlaying        = false
        coverImage       = nil
        loadedArtworkURL = ""
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
        // Re-sync with Spotify's actual position every 30 s to correct accumulated drift.
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
