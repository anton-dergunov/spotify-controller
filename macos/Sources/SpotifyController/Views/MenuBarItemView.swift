import SwiftUI

struct MenuBarItemView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    let onOpenWindow: () -> Void

    @GestureState private var skipPressed = false
    @GestureState private var likePressed = false

    var body: some View {
        if playback.isSpotifyRunning {
            trackInfoView
        } else {
            notRunningView
        }
    }

    // MARK: - Spotify not running

    private var notRunningView: some View {
        Image(systemName: "speaker.zzz.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(nsColor: .labelColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { playback.launchSpotify() }
            .accessibilityLabel("Spotify not running — click to launch")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Spotify running

    private var trackInfoView: some View {
        let oauthAvailable = playback.authService.oauthEnabled && playback.authService.isConnected
        return HStack(spacing: 0) {
            // Track info column: fills remaining width, full-height tap area.
            VStack(spacing: 1) {
                Text(playback.artist.isEmpty ? "Spotify" : playback.artist)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(playback.song.isEmpty ? "Not playing" : playback.song)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenWindow)

            // Skip column: 28 pt wide, spring press animation.
            Image(systemName: "forward.end.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(nsColor: .labelColor))
                .scaleEffect(skipPressed ? 0.75 : 1.0)
                .opacity(skipPressed ? 0.7 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: skipPressed)
                .frame(maxHeight: .infinity)
                .frame(width: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($skipPressed) { _, state, _ in state = true }
                        .onEnded { _ in playback.skipForward() }
                )
                .accessibilityLabel("Next track")
                .accessibilityAddTraits(.isButton)

            // Like column: 28 pt wide, spring press animation.
            Image(systemName: oauthAvailable ? (playback.isLiked ? "heart.fill" : "heart") : "heart.slash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(playback.isLiked && oauthAvailable ? Color.white : Color(nsColor: .labelColor))
                .opacity(oauthAvailable ? (likePressed ? 0.7 : 1.0) : 0.4)
                .scaleEffect(likePressed ? 0.75 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: likePressed)
                .frame(maxHeight: .infinity)
                .frame(width: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($likePressed) { _, state, _ in state = true }
                        .onEnded { _ in if oauthAvailable { playback.toggleLike() } }
                )
                .accessibilityLabel(oauthAvailable ? (playback.isLiked ? "Unlike" : "Like") : "Like unavailable")
                .accessibilityAddTraits(.isButton)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
