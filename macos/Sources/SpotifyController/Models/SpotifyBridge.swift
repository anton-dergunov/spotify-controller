import AppKit
import Foundation

struct SpotifyTrackInfo {
    let name: String
    let artist: String
    let album: String
    let albumYear: Int
    let duration: TimeInterval  // seconds
    let artworkURL: String
    let trackId: String         // Spotify track ID (the part after "spotify:track:")
}

enum SpotifyPlayerState {
    case playing(position: TimeInterval)
    case paused(position: TimeInterval)
    case stopped
}

// @unchecked Sendable: always accessed from the main thread; safe.
final class SpotifyBridge: NSObject, @unchecked Sendable {

    var onRunningChanged: ((Bool) -> Void)?
    var onTrackChanged: ((SpotifyTrackInfo) -> Void)?
    var onStateChanged: ((SpotifyPlayerState) -> Void)?

    private var distributedObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        setupWorkspaceObservers()
        setupDistributedObserver()
    }

    deinit {
        if let obs = distributedObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        workspaceObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    // MARK: - State queries

    func isRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.spotify.client"
        }
    }

    func queryCurrentState() {
        Task { [weak self] in await self?.fetchAndDispatchState() }
    }

    func queryPosition() async -> TimeInterval? {
        let script = """
        tell application "Spotify"
            if it is running then
                return player position as string
            else
                return "not_running"
            end if
        end tell
        """
        guard let output = await osascript(script), output != "not_running" else { return nil }
        return Double(output)
    }

    // MARK: - Commands

    func play()          { run("tell application \"Spotify\" to play") }
    func pause()         { run("tell application \"Spotify\" to pause") }
    func nextTrack()     { run("tell application \"Spotify\" to next track") }
    func previousTrack() { run("tell application \"Spotify\" to previous track") }

    func seek(to seconds: TimeInterval) {
        run("tell application \"Spotify\" to set player position to \(seconds)")
    }

    func launchSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Artwork

    /// Downloads raw bytes from `urlString`. Caller creates NSImage on the main actor,
    /// keeping NSImage (non-Sendable) away from concurrency boundaries.
    func downloadArtwork(from urlString: String) async -> Data? {
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    /// iTunes Search API fallback: finds artwork by artist + track name.
    /// Works for virtually all mainstream music; no API key required.
    func searchITunesArtwork(artist: String, track: String) async -> Data? {
        let query = "\(artist) \(track)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://itunes.apple.com/search?term=\(query)&entity=song&limit=5"
        guard let url = URL(string: urlStr) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]],
            let first   = results.first,
            let thumb   = first["artworkUrl100"] as? String
        else { return nil }
        // The iTunes thumbnail URL ends in "100x100bb.jpg"; swap to 600×600.
        let highRes = thumb
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100",   with: "600x600")
        return await downloadArtwork(from: highRes)
    }

    // MARK: - Private

    private func setupWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        let launched = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                app.bundleIdentifier == "com.spotify.client"
            else { return }
            self?.onRunningChanged?(true)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.fetchAndDispatchState()
            }
        }

        let terminated = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                app.bundleIdentifier == "com.spotify.client"
            else { return }
            self?.onRunningChanged?(false)
        }

        workspaceObservers = [launched, terminated]
    }

    private func setupDistributedObserver() {
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handlePlaybackNotification(notification)
        }
    }

    private func handlePlaybackNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }

        let stateStr  = info["Player State"]    as? String ?? ""
        let position  = info["Playback Position"] as? Double ?? 0
        let name      = info["Name"]   as? String ?? ""
        let artist    = info["Artist"] as? String ?? ""
        let album     = info["Album"]  as? String ?? ""
        let durationMs = info["Duration"] as? Double ?? 0
        let rawURI    = info["Track ID"] as? String ?? ""
        let trackId   = rawURI.components(separatedBy: ":").last ?? ""

        let state: SpotifyPlayerState
        switch stateStr {
        case "Playing": state = .playing(position: position)
        case "Paused":  state = .paused(position: position)
        default:        state = .stopped
        }
        // Dispatch track info first so duration is available before applyPlayerState runs.
        onTrackChanged?(SpotifyTrackInfo(
            name: name, artist: artist, album: album,
            albumYear: 0,
            duration: durationMs / 1000.0,
            artworkURL: "",  // follow-up query provides the URL
            trackId: trackId
        ))
        onStateChanged?(state)

        if !name.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                await self?.fetchAndDispatchState()
            }
        }
    }

    // @MainActor guarantees we're back on the main thread after each `await`,
    // so callbacks can be called directly without DispatchQueue.main.async.
    @MainActor
    private func fetchAndDispatchState() async {
        // Each property in its own try block so a failure on one (e.g. year)
        // does not prevent the others (especially duration) from being read.
        let script = """
        tell application "Spotify"
            if it is running then
                set ps  to player state as string
                set pos to player position
                set n   to ""
                set ar  to ""
                set al  to ""
                set yr  to "0"
                set dur to "0"
                set art to ""
                set uri to ""
                try
                    set n   to name   of current track
                    set ar  to artist of current track
                    set al  to album  of current track
                    set uri to id of current track
                on error
                end try
                try
                    set yr to (year of current track) as string
                on error
                end try
                try
                    set dur to (duration of current track) as string
                on error
                end try
                try
                    set art to artwork url of current track
                on error
                end try
                return ps & linefeed & (pos as string) & linefeed & n & linefeed & ar & linefeed & al & linefeed & yr & linefeed & dur & linefeed & art & linefeed & uri
            else
                return "not_running"
            end if
        end tell
        """

        guard let output = await osascript(script) else {
            NSLog("[SpotifyBridge] fetchAndDispatchState: AppleScript returned nil")
            return
        }

        NSLog("[SpotifyBridge] raw output: %@", String(output.prefix(300)))

        if output == "not_running" {
            onRunningChanged?(false)
            return
        }

        let parts    = output.components(separatedBy: "\n")
        guard parts.count >= 2 else {
            NSLog("[SpotifyBridge] unexpected part count: %d", parts.count)
            return
        }

        let stateStr = parts[0]
        let position = Double(parts[1]) ?? 0
        let name     = parts.count > 2 ? parts[2] : ""
        let artist   = parts.count > 3 ? parts[3] : ""
        let album    = parts.count > 4 ? parts[4] : ""
        let year     = parts.count > 5 ? Int(parts[5])    ?? 0   : 0
        let rawDur   = parts.count > 6 ? Double(parts[6]) ?? 0.0 : 0.0
        let artURL   = parts.count > 7 ? parts[7] : ""
        let rawURI   = parts.count > 8 ? parts[8] : ""

        // Spotify AppleScript returns duration in milliseconds.
        let duration = rawDur / 1000.0
        let trackId  = rawURI.components(separatedBy: ":").last ?? ""

        NSLog("[SpotifyBridge] parsed: state=%@ pos=%.1f name=%@ rawDur=%.0f duration=%.1f", stateStr, position, name, rawDur, duration)

        let state: SpotifyPlayerState
        switch stateStr.lowercased() {
        case "playing": state = .playing(position: position)
        case "paused":  state = .paused(position: position)
        default:        state = .stopped
        }

        onTrackChanged?(SpotifyTrackInfo(
            name: name, artist: artist, album: album,
            albumYear: year, duration: duration, artworkURL: artURL,
            trackId: trackId
        ))
        onStateChanged?(state)
    }

    private func run(_ script: String) {
        Task { await osascript(script) }
    }
}

@discardableResult
private func osascript(_ script: String) async -> String? {
    await withCheckedContinuation { continuation in
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments     = ["-e", script]
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError  = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text.flatMap { $0.isEmpty ? nil : $0 })
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
