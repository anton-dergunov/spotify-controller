import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: SpotifyAuthService
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            likeSection
                .padding(.bottom, 20)

            Divider()
                .padding(.bottom, 16)

            HStack {
                Spacer()
                Button("Done") { onClose?() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Like / Unlike section

    private var likeSection: some View {
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
                credentialsForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.oauthEnabled)
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

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
}
