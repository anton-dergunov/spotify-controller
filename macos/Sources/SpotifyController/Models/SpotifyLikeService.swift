import Foundation

@MainActor
final class SpotifyLikeService {

    weak var authService: SpotifyAuthService?

    func fetchLikedStatus(trackId: String) async -> Bool? {
        guard !trackId.isEmpty else { return nil }
        guard let auth = authService, auth.oauthEnabled, auth.isConnected else { return nil }
        guard let token = await auth.getValidToken() else { return nil }

        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/tracks/contains?ids=\(trackId)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let flags = try? JSONSerialization.jsonObject(with: data) as? [Bool],
              let isLiked = flags.first else { return nil }
        return isLiked
    }

    func setLike(trackId: String, wantLiked: Bool) async -> Bool? {
        guard !trackId.isEmpty else { return nil }
        guard let auth = authService, auth.oauthEnabled, auth.isConnected else { return nil }
        guard let token = await auth.getValidToken() else { return nil }

        // Verify current state before mutating to avoid redundant API calls.
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
              (200...299).contains((mutResp as? HTTPURLResponse)?.statusCode ?? 0) else { return nil }
        return wantLiked
    }
}
