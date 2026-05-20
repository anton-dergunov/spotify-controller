import SwiftUI

struct MenuBarItemView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    let onOpenWindow: () -> Void

    var body: some View {
        if playback.isSpotifyRunning {
            trackInfoView
        } else {
            notRunningView
        }
    }

    // MARK: - Spotify not running

    private var notRunningView: some View {
        // speaker.zzz.fill = "the speaker is sleeping" — funny, music-related,
        // and immediately clear that something audio-adjacent is inactive.
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
        HStack(spacing: 0) {
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

            // Skip column: 28 pt wide, full bar height.
            // Using Image + onTapGesture (not Button) so that contentShape(Rectangle())
            // reliably covers the whole strip, not just the icon's rendered pixels.
            Image(systemName: "forward.end.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(maxHeight: .infinity)
                .frame(width: 28)
                .contentShape(Rectangle())
                .onTapGesture { playback.skipForward() }
                .accessibilityLabel("Next track")
                .accessibilityAddTraits(.isButton)

            // Like column: 28 pt wide, full bar height.
            // Liked state shows a solid white heart.
            Image(systemName: playback.isLiked ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(playback.isLiked ? Color.white : Color(nsColor: .labelColor))
                .frame(maxHeight: .infinity)
                .frame(width: 28)
                .contentShape(Rectangle())
                .onTapGesture { playback.toggleLike() }
                .accessibilityLabel(playback.isLiked ? "Unlike" : "Like")
                .accessibilityAddTraits(.isButton)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
