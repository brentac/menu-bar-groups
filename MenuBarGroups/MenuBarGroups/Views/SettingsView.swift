import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var jamfURL = UserDefaults.standard.string(forKey: "jamfURL") ?? ""
    @State private var clientID = UserDefaults.standard.string(forKey: "clientID") ?? ""
    @State private var clientSecret = ""
    @State private var refreshIntervalMinutes = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes") > 0 ? UserDefaults.standard.integer(forKey: "refreshIntervalMinutes") : 5
    @State private var hideDockIcon = UserDefaults.standard.bool(forKey: "hideDockIcon")
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastAuthSuccess: Date?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .foregroundColor(lastAuthSuccess != nil ? .green : .gray)
                    .font(.system(size: 8))
                Text("Authentication Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Form {
                Section("Jamf Pro Server") {
                    TextField("Server URL", text: $jamfURL)
                        .textContentType(.URL)
                }
                .padding(.vertical, 4)

                Section("API Credentials") {
                    TextField("Client ID", text: $clientID)
                        .autocorrectionDisabled()
                        .textContentType(.username)

                    SecureField("Client Secret", text: $clientSecret)
                        .textContentType(.password)
                }
                .padding(.vertical, 4)

                Section("Refresh Interval") {
                    Stepper("Every \(refreshIntervalMinutes) minute(s)", value: $refreshIntervalMinutes, in: 1...60)
                }
                .padding(.vertical, 4)

                Section("Appearance") {
                    Toggle("Hide Dock Icon", isOn: $hideDockIcon)
                }
                .padding(.vertical, 4)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: saveSettings) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .frame(width: 400, height: 500)
        .onAppear {
            // Load existing secret from keychain
            if let savedSecret = KeychainService.shared.read(account: "clientSecret") {
                clientSecret = savedSecret
            }
            // Load last auth success timestamp
            if let timestamp = UserDefaults.standard.object(forKey: "lastAuthSuccess") as? Double {
                lastAuthSuccess = Date(timeIntervalSince1970: timestamp)
            }
        }
    }

    private func saveSettings() {
        errorMessage = nil
        isLoading = true

        // Validate inputs
        guard !jamfURL.isEmpty, !clientID.isEmpty, !clientSecret.isEmpty else {
            errorMessage = "All fields are required"
            isLoading = false
            return
        }

        Task {
            do {
                // Save to UserDefaults
                UserDefaults.standard.set(jamfURL, forKey: "jamfURL")
                UserDefaults.standard.set(clientID, forKey: "clientID")
                UserDefaults.standard.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes")
                UserDefaults.standard.set(hideDockIcon, forKey: "hideDockIcon")

                // Apply Dock visibility immediately
                if hideDockIcon {
                    NSApplication.shared.setActivationPolicy(.accessory)
                } else {
                    NSApplication.shared.setActivationPolicy(.regular)
                }

                // Save secret to Keychain
                try KeychainService.shared.save(secret: clientSecret, account: "clientSecret")

                // Test authentication
                JamfService.shared.clearToken()
                _ = try await JamfService.shared.getBearerToken()

                // Mark successful authentication
                lastAuthSuccess = Date()
                UserDefaults.standard.set(lastAuthSuccess?.timeIntervalSince1970 ?? 0, forKey: "lastAuthSuccess")

                // Notify app to restart refresh timer
                NotificationCenter.default.post(name: NSNotification.Name("RefreshSettingsChanged"), object: nil)

                DispatchQueue.main.async {
                    isLoading = false
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Authentication failed: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }


}

#Preview {
    SettingsView()
}
