import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: SpotifyAuthService
    @EnvironmentObject private var menuBar: MenuBarSettings
    @EnvironmentObject private var hotkeys: HotkeySettings

    private enum Tab: Hashable, CaseIterable {
        case spotify, menuBar, shortcuts

        var title: String {
            switch self {
            case .spotify:   "Spotify"
            case .menuBar:   "Menu Bar"
            case .shortcuts: "Shortcuts"
            }
        }

        var icon: String {
            switch self {
            case .spotify:   "music.note.list"
            case .menuBar:   "menubar.rectangle"
            case .shortcuts: "keyboard"
            }
        }
    }

    @State private var selectedTab: Tab = .spotify

    var body: some View {
        HStack(spacing: 0) {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
            }
            .listStyle(.sidebar)
            .frame(width: 160)

            Divider()

            ScrollView {
                detailContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .spotify:   spotifyContent
        case .menuBar:   menuBarContent
        case .shortcuts: shortcutsContent
        }
    }

    // MARK: - Spotify tab

    private var spotifyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $auth.oauthEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable Like / Unlike")
                        .font(.headline)
                    Text("Connect a Spotify Developer App to like or unlike tracks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if auth.oauthEnabled {
                Divider()
                credentialsForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.oauthEnabled)
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Client ID",    $auth.clientId)
            field("Redirect URI", $auth.redirectURI)
            connectRow

            if let err = auth.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var connectRow: some View {
        HStack(spacing: 10) {
            if auth.isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Disconnect", role: .destructive) { auth.disconnect() }
                    .controlSize(.small)
            } else {
                Button(auth.isAuthenticating ? "Connecting…" : "Connect with Spotify") {
                    Task { await auth.authorize() }
                }
                .disabled(auth.clientId.isEmpty || auth.isAuthenticating)
                .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .frame(width: 86, alignment: .trailing)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
        }
    }

    // MARK: - Menu Bar tab

    private var menuBarContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            elementsSection

            if menuBar.showTrackInfo {
                Divider()
                trackInfoSection
            }

            if menuBar.showPreviousTrack || menuBar.showPlayPause || menuBar.showNextTrack || menuBar.showLikeButton {
                Divider()
                buttonsSection
            }

            Divider()
            colorsSection

            Divider()
            albumArtSection

            Divider()
            layoutSection

            Divider()
            HStack {
                Spacer()
                Button("Restore Defaults") { menuBar.resetToDefaults() }
                    .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
    }

    private var elementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "Elements",
                subtitle: "Toggle visibility · drag rows to reorder"
            )
            List {
                ForEach(menuBar.elementOrder) { element in
                    HStack(spacing: 10) {
                        Image(systemName: element.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(element.title)
                        Spacer()
                        Toggle("", isOn: visibilityBinding(for: element))
                            .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    menuBar.elementOrder.move(fromOffsets: from, toOffset: to)
                }
            }
            .frame(height: 210)
            .scrollContentBackground(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08))
            )
        }
    }

    private var trackInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Track Info Appearance")

            Toggle("Second line", isOn: $menuBar.showTwoLines)
                .toggleStyle(.switch)

            lineBlock(label: "Line 1",
                      template: $menuBar.line1Template,
                      size: $menuBar.artistFontSize,
                      bold: $menuBar.artistBold)

            if menuBar.showTwoLines {
                Divider()
                lineBlock(label: "Line 2",
                          template: $menuBar.line2Template,
                          size: $menuBar.songFontSize,
                          bold: $menuBar.songBold,
                          showDim: true,
                          dim: $menuBar.dimSecondLine)
            }

            Text("Available fields:  {artist}  ·  {song}  ·  {album}  ·  {year}")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Button Appearance")
            sliderRow(label: "Icon size",
                      value: $menuBar.buttonIconSize,
                      range: 10...22,
                      unit: "pt")
            sliderRow(label: "Column width",
                      value: $menuBar.buttonColumnWidth,
                      range: 20...44,
                      unit: "pt")
        }
    }

    private var albumArtSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Album Art")

            if menuBar.showAlbumArtThumb {
                sliderRow(label: "Thumb size",
                          value: $menuBar.albumArtThumbSize,
                          range: 12...28,
                          unit: "pt")
                stylePickerRow(label: "Thumb style",
                               selection: $menuBar.albumArtThumbStyle)
            }

            Toggle(isOn: $menuBar.showAlbumArtBackground) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show as background")
                    Text("Fills the entire menu bar area behind all other elements.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if menuBar.showAlbumArtBackground {
                stylePickerRow(label: "Style", selection: $menuBar.albumArtBgStyle)
                HStack(spacing: 8) {
                    Text("Opacity")
                        .frame(width: 86, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Slider(value: $menuBar.albumArtBgOpacity, in: 0.05...0.95, step: 0.05)
                    Text("\(Int(menuBar.albumArtBgOpacity * 100))%")
                        .frame(width: 46, alignment: .trailing)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Layout")
            sliderRow(label: "Item width",
                      value: $menuBar.itemWidth,
                      range: 80...300,
                      step: 5,
                      unit: "pt")
        }
    }

    // MARK: - Colors section

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Colors")
            HStack(spacing: 10) {
                Text("Elements")
                    .frame(width: 86, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Toggle("Custom", isOn: $menuBar.useCustomForeground)
                    .controlSize(.small)
                if menuBar.useCustomForeground {
                    ColorPicker("", selection: colorBinding, supportsOpacity: true)
                        .labelsHidden()
                        .frame(width: 28)
                }
                Spacer()
            }
            if !menuBar.useCustomForeground {
                Text("Adapts automatically to light and dark mode.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(red: menuBar.foregroundRed,
                      green: menuBar.foregroundGreen,
                      blue: menuBar.foregroundBlue,
                      opacity: menuBar.foregroundAlpha)
            },
            set: { color in
                if let ns = NSColor(color).usingColorSpace(.sRGB) {
                    menuBar.foregroundRed   = Double(ns.redComponent)
                    menuBar.foregroundGreen = Double(ns.greenComponent)
                    menuBar.foregroundBlue  = Double(ns.blueComponent)
                    menuBar.foregroundAlpha = Double(ns.alphaComponent)
                }
            }
        )
    }

    // MARK: - Reusable row helpers

    @ViewBuilder
    private func lineBlock(
        label: String,
        template: Binding<String>,
        size: Binding<Double>,
        bold: Binding<Bool>,
        showDim: Bool = false,
        dim: Binding<Bool> = .constant(false)
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text("Template")
                    .frame(width: 60, alignment: .trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. {artist}", text: template)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }
            HStack(spacing: 8) {
                Text("Font")
                    .frame(width: 60, alignment: .trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: size, in: 8...18, step: 1)
                Text("\(Int(size.wrappedValue)) pt")
                    .frame(width: 34, alignment: .trailing)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Toggle("Bold", isOn: bold)
                    .controlSize(.small)
                if showDim {
                    Toggle("Dim", isOn: dim)
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func stylePickerRow(
        label: String,
        selection: Binding<AlbumArtStyle>
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 86, alignment: .trailing)
                .foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(AlbumArtStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        unit: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 86, alignment: .trailing)
                .foregroundStyle(.secondary)
            Slider(value: value, in: range, step: step)
            Text("\(Int(value.wrappedValue)) \(unit)")
                .frame(width: 46, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shortcuts tab

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            mediaKeysSection
            Divider()
            customShortcutsSection
            Spacer(minLength: 0)
        }
    }

    private var mediaKeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "Playback",
                subtitle: "Handled by media keys — no configuration needed."
            )
            mediaKeyRow("Previous",     icon: "backward.fill",  badge: "⏮")
            mediaKeyRow("Play / Pause", icon: "playpause.fill", badge: "⏯")
            mediaKeyRow("Next",         icon: "forward.fill",   badge: "⏭")
        }
    }

    @ViewBuilder
    private func mediaKeyRow(_ label: String, icon: String, badge: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.tertiary).frame(width: 18)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(badge).font(.title3).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 1)
    }

    private var customShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Custom Shortcuts")
            HStack(spacing: 8) {
                Text("Like / Unlike")
                    .frame(width: 86, alignment: .trailing)
                    .foregroundStyle(.secondary)
                KeyRecorderField(shortcut: $hotkeys.likeShortcut)
                    .frame(width: 140, height: 22)
            }
        }
    }

    // MARK: - Visibility binding helper

    private func visibilityBinding(for element: MenuBarElement) -> Binding<Bool> {
        switch element {
        case .albumArtThumb:  return $menuBar.showAlbumArtThumb
        case .trackInfo:      return $menuBar.showTrackInfo
        case .previousTrack:  return $menuBar.showPreviousTrack
        case .playPause:      return $menuBar.showPlayPause
        case .nextTrack:      return $menuBar.showNextTrack
        case .like:           return $menuBar.showLikeButton
        }
    }
}

// MARK: - SectionHeader

private struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
