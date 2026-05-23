import SwiftUI

struct PlayerPopoverView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    @State private var isHovering = false
    @State private var heartScale: CGFloat = 1.0

    private var controlsVisible: Bool { isHovering }

    private var likeAvailable: Bool { playback.isLikeAvailable }

    var body: some View {
        ZStack {
            if playback.song.isEmpty {
                idleLayer
            } else {
                coverLayer
                ZStack {
                    blurredCoverLayer
                    tintLayer
                    controlsLayer
                }
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
            }
        }
        .frame(width: PlayerTheme.popoverSize, height: PlayerTheme.popoverSize)
        .clipShape(RoundedRectangle(cornerRadius: PlayerTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PlayerTheme.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: PlayerTheme.cornerRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(hoverAnimation(for: hovering)) {
                isHovering = hovering
            }
        }
        .onChange(of: playback.isLiked, perform: { newValue in
            guard newValue, likeAvailable else { return }
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) { heartScale = 1.4 }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { heartScale = 1.0 }
            }
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel(controlsVisible ? "Now playing with controls" : "Now playing")
    }

    @ViewBuilder
    private var idleLayer: some View {
        ZStack {
            Color(white: 0.18)
            VStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.30))
                Text("Nothing playing")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    @ViewBuilder
    private var coverLayer: some View {
        CoverImageView(image: playback.coverImage)
            .frame(width: PlayerTheme.popoverSize, height: PlayerTheme.popoverSize)
    }

    @ViewBuilder
    private var blurredCoverLayer: some View {
        CoverImageView(image: playback.coverImage)
            .frame(width: PlayerTheme.popoverSize, height: PlayerTheme.popoverSize)
            .scaleEffect(PlayerTheme.blurScale)
            .blur(radius: PlayerTheme.blurRadius)
            .clipped()
    }

    private var tintLayer: some View {
        PlayerTheme.tintColor
            .opacity(PlayerTheme.tintOpacity)
    }

    private var controlsLayer: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                centerBlock
                Spacer(minLength: 0)
                bottomScrubber
            }

            transportRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var topBar: some View {
        HStack {
            ControlIconButton(
                title: likeAvailable
                    ? (playback.isLiked ? "Remove from Liked Songs" : "Save to Liked Songs")
                    : "Like unavailable — enable Spotify or Logging in Settings",
                size: PlayerTheme.cornerHitSize
            ) {
                if likeAvailable { playback.toggleLike() }
            } label: {
                Image(systemName: likeAvailable
                      ? (playback.isLiked ? "heart.fill" : "heart")
                      : "heart.slash")
                    .font(.system(size: PlayerTheme.utilityIconSize, weight: .medium))
                    .foregroundStyle(PlayerTheme.controlForeground)
                    .scaleEffect(heartScale)
                    .modifier(ShakeEffect(animatableData: CGFloat(playback.likeShakeCount)))
                    .animation(.linear(duration: 0.4), value: playback.likeShakeCount)
                    .opacity(likeAvailable ? 1.0 : 0.45)
            }

            Spacer()

            if !playback.currentTrackId.isEmpty {
                ControlIconButton(title: "Open in Spotify", size: PlayerTheme.cornerHitSize) {
                    playback.openInSpotify()
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: PlayerTheme.utilityIconSize, weight: .medium))
                        .foregroundStyle(PlayerTheme.controlForeground)
                }
            }

            Spacer()

            ControlIconButton(title: "Settings", size: PlayerTheme.cornerHitSize) {
                SettingsWindowController.shared.show(authService: playback.authService)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: PlayerTheme.utilityIconSize, weight: .medium))
                    .foregroundStyle(PlayerTheme.controlForeground)
            }
        }
    }

    private var centerBlock: some View {
        VStack(spacing: 0) {
            Text(playback.artist)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PlayerTheme.controlForeground)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            Color.clear
                .frame(height: PlayerTheme.playButtonSize)
                .padding(.bottom, 14)

            Text(playback.song)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PlayerTheme.controlForeground)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            Text(playback.albumSubtitle)
                .font(.system(size: 11))
                .foregroundStyle(PlayerTheme.controlForegroundMuted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var transportRow: some View {
        HStack {
            ControlIconButton(title: "Previous", size: PlayerTheme.cornerHitSize) {
                playback.skipBackward()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: PlayerTheme.skipIconSize))
                    .foregroundStyle(PlayerTheme.controlForeground)
            }

            Spacer()

            Button {
                playback.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
                        }
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: PlayerTheme.playIconSize, weight: .bold))
                        .foregroundStyle(PlayerTheme.controlForeground)
                        .offset(x: playback.isPlaying ? 0 : 2)
                }
                .frame(width: PlayerTheme.playButtonSize, height: PlayerTheme.playButtonSize)
            }
            .buttonStyle(SpringyButtonStyle(scale: 0.88))
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Spacer()

            ControlIconButton(title: "Next", size: PlayerTheme.cornerHitSize) {
                playback.skipForward()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: PlayerTheme.skipIconSize))
                    .foregroundStyle(PlayerTheme.controlForeground)
            }
        }
        .padding(.horizontal, 4)
        .offset(y: -8)
    }

    private var bottomScrubber: some View {
        VStack(spacing: 4) {
            PlaybackScrubber(
                fraction: playback.progressFraction,
                onSeek: { playback.seek(fraction: $0) }
            )

            HStack {
                Text(TimeFormatting.format(playback.progress))
                Spacer()
                Text(TimeFormatting.format(playback.duration))
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(PlayerTheme.controlForegroundMuted)
        }
    }

    private func hoverAnimation(for hovering: Bool) -> Animation {
        if hovering {
            return .easeInOut(duration: PlayerTheme.hoverFadeIn).delay(PlayerTheme.hoverFadeDelay)
        }
        return .easeInOut(duration: PlayerTheme.hoverFadeOut)
    }
}

// MARK: - SpringyButtonStyle

private struct SpringyButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.82

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - CoverImageView

private struct CoverImageView: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.18)
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .clipped()
    }
}

// MARK: - ControlIconButton

private struct ControlIconButton<Label: View>: View {
    let title: String
    let size: CGFloat
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(SpringyButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - PlaybackScrubber

private struct PlaybackScrubber: View {
    let fraction: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PlayerTheme.scrubberTrack)
                    .frame(height: 5)

                Capsule()
                    .fill(PlayerTheme.controlForeground)
                    .frame(width: max(0, geometry.size.width * fraction), height: 5)

                Circle()
                    .fill(PlayerTheme.controlForeground)
                    .frame(width: 11, height: 11)
                    .offset(x: max(0, geometry.size.width * fraction - 5.5))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let f = value.location.x / max(geometry.size.width, 1)
                        onSeek(f)
                    }
            )
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
