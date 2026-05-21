import Foundation

struct LikeResult {
    let isLiked: Bool
    let artworkURL: String?
}

// Native-Swift port of prototypes/spotify_liked.py.
//
//   1. Fast path  – inject JS into an open Chrome tab on the track's page.
//   2. WKWebView  – persistent off-screen WebKit view with the user's Chrome cookies,
//                   navigates to the track page and reads/clicks the DOM button.
//                   This is the native equivalent of the Python script's Playwright fallback.
//
// No OAuth / no Spotify Developer API:
//   • Spotify locked down Web API access for new developer apps in Feb 2026.
//   • The open.spotify.com/get_access_token endpoint requires a rotating TOTP
//     (since March 2025) and cannot be called from a script.
//   • The Spotify desktop AppleScript dictionary exposes `starred` as read-only —
//     no way to set library status via AppleScript.
@MainActor
final class SpotifyLikeService {

    weak var authService: SpotifyAuthService?

    // MARK: - Public API

    /// Called when a new track starts playing.
    func fetchLikeAndArtwork(trackId: String) async -> LikeResult? {
        guard !trackId.isEmpty else {
            log("fetchLikeAndArtwork: trackId empty, skipping")
            return nil
        }
        log("fetchLikeAndArtwork: trackId=\(trackId)")

        // 1. Chrome tab fast path (zero extra network traffic when Chrome has the page open)
        if let r = await chromeFetchLike(trackId: trackId) {
            log("fetchLikeAndArtwork: chrome path succeeded, isLiked=\(r.isLiked)")
            return r
        }
        log("fetchLikeAndArtwork: chrome path failed")

        // 2. OAuth API (if user configured it in Settings)
        if let r = await oauthFetchLike(trackId: trackId) {
            log("fetchLikeAndArtwork: OAuth path succeeded, isLiked=\(r.isLiked)")
            return r
        }

        // 3. WKWebView with Chrome cookies (matches Python's playwright fallback)
        log("fetchLikeAndArtwork: trying WKWebView")
        if let isLiked = await SpotifyWebController.shared.read(trackId: trackId) {
            log("fetchLikeAndArtwork: WKWebView returned isLiked=\(isLiked)")
            return LikeResult(isLiked: isLiked, artworkURL: nil)
        }
        log("fetchLikeAndArtwork: all paths failed")
        return nil
    }

    /// Called when the user taps the heart button.
    /// `wantLiked` is the UI's intended new state.
    func setLike(trackId: String, wantLiked: Bool) async -> Bool? {
        guard !trackId.isEmpty else {
            log("setLike: trackId empty, skipping")
            return nil
        }
        log("setLike: trackId=\(trackId) wantLiked=\(wantLiked)")

        // 1. Chrome tab fast path
        if let r = await chromeSetLike(trackId: trackId, wantLiked: wantLiked) {
            log("setLike: chrome path succeeded, actual=\(r)")
            return r
        }
        log("setLike: chrome path failed")

        // 2. OAuth API (if configured)
        if let r = await oauthSetLike(trackId: trackId, wantLiked: wantLiked) {
            log("setLike: OAuth path succeeded, actual=\(r)")
            return r
        }

        // 3. WKWebView (handles reconciliation internally: only clicks if state differs)
        log("setLike: trying WKWebView")
        if let result = await SpotifyWebController.shared.setLike(trackId: trackId,
                                                                    wantLiked: wantLiked) {
            log("setLike: WKWebView returned \(result)")
            return result
        }
        log("setLike: all paths failed")
        return nil
    }

    // MARK: - OAuth API (optional, only when user configured it)

    private func oauthFetchLike(trackId: String) async -> LikeResult? {
        guard let auth = authService, auth.isConnected else { return nil }
        guard let token = await auth.getValidToken() else {
            log("OAuth: connected but token unavailable")
            return nil
        }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/tracks/contains?ids=\(trackId)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let flags = try? JSONSerialization.jsonObject(with: data) as? [Bool],
              let isLiked = flags.first else {
            log("OAuth: fetch request failed (status=\(((try? await URLSession.shared.data(for: req).1) as? HTTPURLResponse)?.statusCode ?? -1))")
            return nil
        }
        return LikeResult(isLiked: isLiked, artworkURL: nil)
    }

    private func oauthSetLike(trackId: String, wantLiked: Bool) async -> Bool? {
        guard let auth = authService, auth.isConnected else { return nil }
        guard let token = await auth.getValidToken() else { return nil }

        // Read actual state first (reconciliation)
        var checkReq = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/tracks/contains?ids=\(trackId)")!)
        checkReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (checkData, _) = try? await URLSession.shared.data(for: checkReq),
              let flags = try? JSONSerialization.jsonObject(with: checkData) as? [Bool],
              let current = flags.first else { return nil }
        if current == wantLiked { return current }

        var mutReq = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/tracks")!)
        mutReq.httpMethod = wantLiked ? "PUT" : "DELETE"
        mutReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        mutReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        mutReq.httpBody = try? JSONSerialization.data(withJSONObject: ["ids": [trackId]])
        guard let (_, mutResp) = try? await URLSession.shared.data(for: mutReq),
              (200...299).contains((mutResp as? HTTPURLResponse)?.statusCode ?? 0) else {
            log("OAuth: mutation request failed")
            return nil
        }
        return wantLiked
    }

    // MARK: - Chrome AppleScript fast path

    private func chromeFetchLike(trackId: String) async -> LikeResult? {
        log("chrome: trying tab injection for trackId=\(trackId)")
        guard let raw = await injectJSInChrome(trackId: trackId, js: readAndArtJS) else {
            log("chrome: no tab found or Chrome not running")
            return nil
        }
        log("chrome: raw result='\(raw.prefix(120))'")
        let parts = raw.components(separatedBy: "\t")
        guard parts.count >= 2, !parts[0].hasPrefix("ERROR:"), !parts[0].isEmpty,
              let liked = parseLikedState(label: parts[0], checked: parts[1]) else {
            return nil
        }
        let artURL = parts.count >= 3 && !parts[2].isEmpty ? parts[2] : nil
        return LikeResult(isLiked: liked, artworkURL: artURL)
    }

    private func chromeSetLike(trackId: String, wantLiked: Bool) async -> Bool? {
        guard let rawRead = await injectJSInChrome(trackId: trackId, js: readJS) else {
            return nil
        }
        guard let current = parseLikedFromRaw(rawRead) else { return nil }
        if current == wantLiked { return current }

        if let rawClick = await injectJSInChrome(trackId: trackId, js: clickJS),
           let afterClick = parseLikedFromRaw(rawClick) {
            return afterClick
        }
        if let rawReread = await injectJSInChrome(trackId: trackId, js: readJS) {
            return parseLikedFromRaw(rawReread)
        }
        return nil
    }

    private func injectJSInChrome(trackId: String, js: String) async -> String? {
        let escaped = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabUrl to URL of t
                    if tabUrl contains "open.spotify.com/track/\(trackId)" then
                        try
                            return execute javascript "\(escaped)" in t
                        on error errMsg
                            return "ERROR:" & errMsg
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        guard let r = await runOsascript(script), !r.isEmpty else { return nil }
        return r
    }

    // MARK: - JS snippets (same selectors as the Python prototype)

    private let readAndArtJS = """
    (function(){
      var b=document.querySelector('[data-testid="action-bar"] [data-testid="add-button"]')
        ||document.querySelector('button[aria-label="Add to Liked Songs"]')
        ||document.querySelector('button[aria-label="Remove from Liked Songs"]');
      if(!b)return '';
      var og=document.querySelector('meta[property="og:image"]');
      return (b.getAttribute('aria-label')||'')+'\\t'+(b.getAttribute('aria-checked')||'')+'\\t'+(og?og.getAttribute('content'):'');
    })();
    """

    private let readJS = """
    (function(){
      var b=document.querySelector('[data-testid="action-bar"] [data-testid="add-button"]')
        ||document.querySelector('button[aria-label="Add to Liked Songs"]')
        ||document.querySelector('button[aria-label="Remove from Liked Songs"]');
      if(!b)return '';
      return (b.getAttribute('aria-label')||'')+'\\t'+(b.getAttribute('aria-checked')||'');
    })();
    """

    private let clickJS = """
    (function(){
      var b=document.querySelector('[data-testid="action-bar"] [data-testid="add-button"]')
        ||document.querySelector('button[aria-label="Add to Liked Songs"]')
        ||document.querySelector('button[aria-label="Remove from Liked Songs"]');
      if(!b)return '';
      b.click();
      return (b.getAttribute('aria-label')||'')+'\\t'+(b.getAttribute('aria-checked')||'');
    })();
    """

    // MARK: - Parsing

    private func parseLikedFromRaw(_ raw: String) -> Bool? {
        guard !raw.isEmpty, !raw.hasPrefix("ERROR:"), raw.contains("\t") else { return nil }
        let p = raw.components(separatedBy: "\t")
        guard !p[0].isEmpty else { return nil }
        return parseLikedState(label: p[0], checked: p.count > 1 ? p[1] : "")
    }

    private func parseLikedState(label: String, checked: String) -> Bool? {
        if label.contains("Remove from Liked Songs") || label.contains("Remove from Your Library") {
            return true
        }
        if label.contains("Add to Liked Songs") || label.contains("Save to Your Library") {
            return checked == "true"
        }
        if checked == "true"  { return true  }
        if checked == "false" { return false }
        return nil
    }

    // MARK: - Logging

    private func log(_ message: String) {
        NSLog("[SpotifyLike] %@", message)
    }
}

// MARK: - osascript helper

@discardableResult
private func runOsascript(_ script: String) async -> String? {
    await withCheckedContinuation { cont in
        Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError  = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: text.flatMap { $0.isEmpty ? nil : $0 })
            } catch {
                cont.resume(returning: nil)
            }
        }
    }
}
