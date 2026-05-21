import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: SpotifyAuthService
    var onClose: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cookieFallbackSection

                Divider()

                oauthSection

                Divider()

                HStack {
                    Spacer()
                    Button("Done") { onClose?() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 460)
        }
        .frame(minHeight: 400, idealHeight: 640, maxHeight: 720)
    }

    // MARK: - WKWebView fallback (always present)

    private var cookieFallbackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Default: Chrome session")
                .font(.headline)
            Text("Like / unlike normally works via your existing Spotify session in Chrome (or Brave / Edge). If a tab is open on the track page, JS is injected directly. Otherwise a hidden WebKit view loads the page with your cookies and clicks the like button.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("If logs show \u{201C}decrypted 0 cookies\u{201D}, the binary likely needs Full Disk Access (System Settings \u{2192} Privacy & Security \u{2192} Full Disk Access \u{2192} add SpotifyController).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - OAuth (optional)

    private var oauthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Optional: Spotify Developer App (OAuth)")
                .font(.headline)

            Text("If you have credentials for an existing Spotify app — your own grandfathered app or any other — you can plug them in here for a fast, native API path. Leave Client Secret empty to use PKCE.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                field("Client ID",     $auth.clientId)
                field("Client Secret", $auth.clientSecret, isSecret: true)
                field("Redirect URI",  $auth.redirectURI)
                field("Scopes",        $auth.scopes)
            }

            HStack(spacing: 12) {
                if auth.isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Button("Disconnect", role: .destructive) { auth.disconnect() }
                } else {
                    Button(auth.isAuthenticating ? "Connecting…" : "Connect with Spotify") {
                        Task { await auth.authorize() }
                    }
                    .disabled(auth.clientId.isEmpty || auth.isAuthenticating)
                    .buttonStyle(.borderedProminent)
                }
            }

            if let err = auth.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func field(_ label: String, _ binding: Binding<String>, isSecret: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 110, alignment: .trailing)
                .font(.caption)
                .foregroundStyle(.secondary)
            if isSecret {
                SecureField("", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            } else {
                TextField("", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }
}
