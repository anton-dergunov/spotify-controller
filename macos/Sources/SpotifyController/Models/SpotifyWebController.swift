import AppKit
import Foundation
import WebKit

// Pure-Swift equivalent of Python's Playwright fallback in prototypes/spotify_liked.py.
// Owns a persistent off-screen WKWebView loaded with the user's Chrome cookies,
// navigates to each track's page, polls the DOM for the like button, reads or clicks it.
//
// First navigation: ~5-15 s (downloads SPA bundle).
// Subsequent navigations: ~1-3 s (resources cached, often SPA-internal routing).
@MainActor
final class SpotifyWebController: NSObject {

    static let shared = SpotifyWebController()

    private var webView:         WKWebView?
    private var offscreenWindow: NSWindow?
    private var cookiesInjected = false
    private var lastLoadedTrackId = ""

    // Serializes navigations: one in flight at a time.
    private var navContinuation: CheckedContinuation<Void, Never>?

    // Serializes read/setLike operations across the whole controller.
    private var inFlight: Task<Void, Never>?

    // MARK: - Public API

    func read(trackId: String) async -> Bool? {
        await waitForInFlight()
        let task = Task<Bool?, Never> { [weak self] in
            guard let self = self else { return nil }
            return await self.doRead(trackId: trackId)
        }
        inFlight = Task { _ = await task.value }
        return await task.value
    }

    func setLike(trackId: String, wantLiked: Bool) async -> Bool? {
        await waitForInFlight()
        let task = Task<Bool?, Never> { [weak self] in
            guard let self = self else { return nil }
            return await self.doSetLike(trackId: trackId, wantLiked: wantLiked)
        }
        inFlight = Task { _ = await task.value }
        return await task.value
    }

    private func waitForInFlight() async {
        if let t = inFlight { await t.value }
    }

    // MARK: - Implementation

    private func doRead(trackId: String) async -> Bool? {
        guard await ensureReady() else { return nil }
        await navigateIfNeeded(trackId: trackId)
        return await pollLikeState(timeout: 30)?.liked
    }

    private func doSetLike(trackId: String, wantLiked: Bool) async -> Bool? {
        guard await ensureReady() else { return nil }
        await navigateIfNeeded(trackId: trackId)

        guard let initial = await pollLikeState(timeout: 30) else { return nil }
        if initial.liked == wantLiked {
            log("already in desired state \(wantLiked)")
            return wantLiked
        }

        log("clicking like button (current=\(initial.liked), want=\(wantLiked))")
        guard await clickLikeButton() else { return nil }

        // Wait up to ~6 s for the button state to reflect the click.
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let s = await currentLikeState(), s.liked == wantLiked {
                return wantLiked
            }
        }
        return await currentLikeState()?.liked
    }

    // MARK: - Setup

    private func ensureReady() async -> Bool {
        if webView != nil, cookiesInjected { return true }

        let cookies = SpotifyChromeCookies.readAllSpotifyCookies()
        guard !cookies.isEmpty else {
            log("ensureReady: no spotify.com cookies decrypted from any browser")
            return false
        }

        let config = WKWebViewConfiguration()
        let wv = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1280, height: 800),
            configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        let win = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 1280, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = wv
        win.orderBack(nil)

        self.webView         = wv
        self.offscreenWindow = win

        let store = wv.configuration.websiteDataStore.httpCookieStore
        for cookie in cookies {
            await store.setCookie(cookie)
        }
        cookiesInjected = true
        log("setup complete with \(cookies.count) cookies")
        return true
    }

    // MARK: - Navigation

    private func navigateIfNeeded(trackId: String) async {
        if lastLoadedTrackId == trackId { return }
        lastLoadedTrackId = trackId
        let url = URL(string: "https://open.spotify.com/track/\(trackId)")!
        log("navigating to \(url.absoluteString)")
        await navigate(to: url)
    }

    private func navigate(to url: URL) async {
        guard let wv = webView else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            // Cancel any previous continuation
            navContinuation?.resume()
            navContinuation = cont
            wv.load(URLRequest(url: url))
        }
    }

    // MARK: - JS

    private struct LikeState { let liked: Bool }

    private let readJS = """
    (function(){
      var b = document.querySelector('[data-testid="action-bar"] [data-testid="add-button"]')
           || document.querySelector('button[aria-label="Add to Liked Songs"]')
           || document.querySelector('button[aria-label="Remove from Liked Songs"]');
      if (!b) return '';
      return (b.getAttribute('aria-label')||'') + '\\t' + (b.getAttribute('aria-checked')||'');
    })();
    """

    private let clickJS = """
    (function(){
      var b = document.querySelector('[data-testid="action-bar"] [data-testid="add-button"]')
           || document.querySelector('button[aria-label="Add to Liked Songs"]')
           || document.querySelector('button[aria-label="Remove from Liked Songs"]');
      if (!b) return false;
      b.click();
      return true;
    })();
    """

    // Polls the page for the like button until it appears (or timeout).
    private func pollLikeState(timeout: TimeInterval) async -> LikeState? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let s = await currentLikeState() { return s }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        log("pollLikeState: timed out after \(timeout)s")
        return nil
    }

    private func currentLikeState() async -> LikeState? {
        guard let raw = await evalString(readJS),
              !raw.isEmpty,
              raw.contains("\t")
        else { return nil }
        let parts = raw.components(separatedBy: "\t")
        guard let liked = parseLikedState(label: parts[0],
                                           checked: parts.count > 1 ? parts[1] : "")
        else { return nil }
        return LikeState(liked: liked)
    }

    private func clickLikeButton() async -> Bool {
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            webView?.evaluateJavaScript(clickJS) { result, _ in
                cont.resume(returning: (result as? Bool) ?? false)
            }
        }
    }

    private func evalString(_ js: String) async -> String? {
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            webView?.evaluateJavaScript(js) { result, _ in
                cont.resume(returning: result as? String)
            }
        }
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
        NSLog("[SpotifyWeb] %@", message)
    }
}

// MARK: - WKNavigationDelegate
//
// Declared nonisolated because WKNavigationDelegate is an @objc protocol; methods are
// inherently called on the main thread by WebKit, so we just hop to the @MainActor.

extension SpotifyWebController: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.resumeNav() }
    }

    nonisolated func webView(_ webView: WKWebView,
                              didFail navigation: WKNavigation!,
                              withError error: Error) {
        Task { @MainActor in self.resumeNav() }
    }

    nonisolated func webView(_ webView: WKWebView,
                              didFailProvisionalNavigation navigation: WKNavigation!,
                              withError error: Error) {
        Task { @MainActor in self.resumeNav() }
    }

    fileprivate func resumeNav() {
        navContinuation?.resume()
        navContinuation = nil
    }
}
