import SwiftUI
import AppKit

struct GroupPickerView: View {
    @State private var computerGroups: [JamfGroup] = []
    @State private var mobileGroups: [JamfGroup] = []
    @State private var selectedGroupIDs: Set<String> = Set()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.title)
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            loadGroups()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if !computerGroups.isEmpty {
                                Text("Computer Groups")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)

                                ForEach(computerGroups) { group in
                                    GroupRow(group: group, isSelected: selectedGroupIDs.contains(groupID(group))) {
                                        toggleGroup(group)
                                    } onRename: {
                                        renameGroup(group)
                                    }
                                    Divider()
                                }
                            }

                            if !mobileGroups.isEmpty {
                                Text("Mobile Device Groups")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)

                                ForEach(mobileGroups) { group in
                                    GroupRow(group: group, isSelected: selectedGroupIDs.contains(groupID(group))) {
                                        toggleGroup(group)
                                    } onRename: {
                                        renameGroup(group)
                                    }
                                    Divider()
                                }
                            }

                            if computerGroups.isEmpty && mobileGroups.isEmpty {
                                Text("No groups available")
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .navigationTitle("Select Groups")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        saveAndDismiss()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            loadGroups()
            loadSelectedGroups()
        }
    }

    private func loadGroups() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let token = try await JamfService.shared.getBearerToken()
                let computerGroupsResult = try await JamfService.shared.fetchComputerGroups(token: token)
                let mobileGroupsResult = try await JamfService.shared.fetchMobileDeviceGroups(token: token)

                DispatchQueue.main.async {
                    self.computerGroups = computerGroupsResult.sorted { $0.name < $1.name }
                    self.mobileGroups = mobileGroupsResult.sorted { $0.name < $1.name }
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load groups: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func loadSelectedGroups() {
        if let saved = UserDefaults.standard.array(forKey: "selectedGroupIDs") as? [String] {
            selectedGroupIDs = Set(saved)
        }
    }

    private func toggleGroup(_ group: JamfGroup) {
        let id = groupID(group)
        if selectedGroupIDs.contains(id) {
            selectedGroupIDs.remove(id)
        } else {
            selectedGroupIDs.insert(id)
        }
    }

    private func saveAndDismiss() {
        UserDefaults.standard.set(Array(selectedGroupIDs), forKey: "selectedGroupIDs")

        // Notify AppDelegate to rebuild status items
        NotificationCenter.default.post(name: NSNotification.Name("SelectedGroupsChanged"), object: nil)

        dismiss()
    }

    private func groupID(_ group: JamfGroup) -> String {
        "\(group.type.rawValue)-\(group.id)"
    }

    private func renameGroup(_ group: JamfGroup) {
        let alert = NSAlert()
        alert.messageText = "Rename Group"
        alert.informativeText = "Enter a custom name for this group (or leave blank to use the original name)"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        let currentName = UserDefaults.standard.string(forKey: "groupDisplayName-\(group.id)") ?? group.name
        textField.stringValue = currentName
        alert.accessoryView = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if newName.isEmpty {
                UserDefaults.standard.removeObject(forKey: "groupDisplayName-\(group.id)")
            } else {
                UserDefaults.standard.set(newName, forKey: "groupDisplayName-\(group.id)")
            }
        }
    }
}

struct GroupRow: View {
    let group: JamfGroup
    let isSelected: Bool
    let action: () -> Void
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in action() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

            Text(group.name)
                .foregroundColor(.primary)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            Button(action: onRename) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

#Preview {
    GroupPickerView()
}
