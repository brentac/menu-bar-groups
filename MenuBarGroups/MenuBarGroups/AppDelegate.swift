import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var mainStatusItem: NSStatusItem?
    var groupStatusItems: [NSStatusItem] = []
    var settingsWindow: NSWindow?
    var groupPickerWindow: NSWindow?
    var mainMenu: NSMenu?
    var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("AppDelegate: applicationDidFinishLaunching")

        // Apply Dock visibility preference
        let hideDockIcon = UserDefaults.standard.bool(forKey: "hideDockIcon")
        if hideDockIcon {
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
        }

        // Hide the main window but don't close it
        DispatchQueue.main.async {
            NSApplication.shared.windows.forEach { window in
                window.orderOut(nil)
            }
        }

        // Always create the main menu bar icon
        createMainMenuItem()

        // Check if we have saved credentials
        let hasCredentials = KeychainService.shared.read(account: "clientSecret") != nil
        print("AppDelegate: hasCredentials = \(hasCredentials)")

        if !hasCredentials {
            // First run: show settings without requiring Touch ID
            print("AppDelegate: First run, showing settings")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.presentSettings()
            }
        } else {
            // Normal launch: build status items
            print("AppDelegate: Normal launch, building status items")
            buildStatusItems()
            scheduleRefresh()
        }

        // Listen for group selection changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onGroupsChanged),
            name: NSNotification.Name("SelectedGroupsChanged"),
            object: nil
        )

        // Listen for refresh settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onRefreshSettingsChanged),
            name: NSNotification.Name("RefreshSettingsChanged"),
            object: nil
        )

        // Listen for manual refresh requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onManualRefreshRequested),
            name: NSNotification.Name("ManualRefreshRequested"),
            object: nil
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Open settings when dock icon is clicked
        presentSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running when all windows close
        return false
    }

    @objc private func onGroupsChanged() {
        buildStatusItems()
    }

    @objc private func onRefreshSettingsChanged() {
        print("AppDelegate: Refresh settings changed, restarting timer")
        scheduleRefresh()
    }

    @objc private func onManualRefreshRequested() {
        print("AppDelegate: Manual refresh requested")
        refreshGroups()
    }

    private func createMainMenuItem() {
        print("AppDelegate: Creating main menu item")

        let statusBar = NSStatusBar.system
        let statusItem = statusBar.statusItem(withLength: 30)

        guard let button = statusItem.button else {
            print("AppDelegate: Failed to get status item button")
            return
        }

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        button.image = NSImage(systemSymbolName: "macbook", accessibilityDescription: "Groups")
        button.title = ""

        // Create menu
        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let groupsItem = NSMenuItem(title: "Groups", action: #selector(showGroupPicker), keyEquivalent: "")
        groupsItem.target = self
        menu.addItem(groupsItem)

        // Placeholder for selected groups (will be populated in menuWillOpen)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        mainStatusItem = statusItem
        mainMenu = menu

        print("AppDelegate: Main menu item created successfully")
    }


    private func groupID(_ group: JamfGroup) -> String {
        "\(group.type.rawValue)-\(group.id)"
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        updateSelectedGroupsInMenu(menu)
    }

    private func updateSelectedGroupsInMenu(_ menu: NSMenu) {
        // Remove all items between Groups and Quit (except Settings and Groups themselves)
        let groupsButtonIndex = menu.items.firstIndex(where: { $0.title == "Groups" }) ?? -1
        let quitIndex = menu.items.firstIndex(where: { $0.title == "Quit" }) ?? -1

        if groupsButtonIndex >= 0 && quitIndex > groupsButtonIndex + 1 {
            // Remove from the end backwards to avoid index shifting issues
            for i in stride(from: quitIndex - 1, through: groupsButtonIndex + 1, by: -1) {
                if i < menu.items.count && i > groupsButtonIndex {
                    menu.removeItem(at: i)
                }
            }
        }

        // Add Refresh Counts button right after Groups
        let groupsIndex = menu.items.firstIndex(where: { $0.title == "Groups" }) ?? 0
        let refreshItem = NSMenuItem(title: "Refresh Counts", action: #selector(self.refreshGroupCountsFromMenu), keyEquivalent: "")
        refreshItem.target = self
        menu.insertItem(refreshItem, at: groupsIndex + 1)

        // Add separator after Refresh button
        menu.insertItem(NSMenuItem.separator(), at: groupsIndex + 2)

        // Fetch and add selected groups with counts
        Task {
            do {
                let token = try await JamfService.shared.getBearerToken()
                let computerGroups = try await JamfService.shared.fetchComputerGroups(token: token)
                let mobileGroups = try await JamfService.shared.fetchMobileDeviceGroups(token: token)
                let allGroups = computerGroups + mobileGroups

                let selectedGroupIDs = Set((UserDefaults.standard.array(forKey: "selectedGroupIDs") as? [String]) ?? [])
                var selectedGroups: [JamfGroup] = []

                for selectedID in selectedGroupIDs {
                    let components = selectedID.split(separator: "-")
                    if components.count == 2, let groupID = Int(components[1]),
                       let group = allGroups.first(where: { $0.id == groupID }) {
                        selectedGroups.append(group)
                    }
                }

                DispatchQueue.main.async {
                    // Find insertion point (after the separator that follows Refresh Counts)
                    let groupsButtonIndex = menu.items.firstIndex(where: { $0.title == "Groups" }) ?? 0
                    var insertIndex = groupsButtonIndex + 3

                    // Add selected groups
                    for group in selectedGroups.sorted(by: { $0.name < $1.name }) {
                        let displayName = UserDefaults.standard.string(forKey: "groupDisplayName-\(group.id)") ?? group.name

                        // Start with placeholder count
                        let item = NSMenuItem(title: "\(displayName) (—)", action: nil, keyEquivalent: "")
                        menu.insertItem(item, at: insertIndex)
                        insertIndex += 1

                        // Fetch actual count
                        Task {
                            do {
                                let count: Int
                                switch group.type {
                                case .computer:
                                    count = try await GroupCounterService.shared.fetchComputerGroupCount(groupId: group.id, token: token)
                                case .mobile:
                                    count = try await GroupCounterService.shared.fetchMobileGroupCount(groupId: group.id, token: token)
                                }

                                DispatchQueue.main.async {
                                    item.title = "\(displayName) (\(count))"
                                }
                            } catch {
                                DispatchQueue.main.async {
                                    item.title = "\(displayName) (?)"
                                }
                            }
                        }
                    }

                    // Add separator before Quit if there are groups
                    if !selectedGroups.isEmpty {
                        let quitIndex = menu.items.firstIndex(where: { $0.title == "Quit" }) ?? menu.items.count - 1
                        menu.insertItem(NSMenuItem.separator(), at: quitIndex)
                    }
                }
            } catch {
                print("Failed to update selected groups in menu: \(error)")
            }
        }
    }

    private func buildStatusItems() {
        // Groups are now only shown in the dropdown menu
        print("AppDelegate: Groups are displayed in dropdown menu only")

        // Remove any existing group status items
        groupStatusItems.forEach { $0.statusBar?.removeStatusItem($0) }
        groupStatusItems.removeAll()
    }

    @objc private func showSettings() {
        presentSettings()
    }

    private func presentSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let hostingController = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Jamf Pro Settings"
            window.setContentSize(NSSize(width: 450, height: 600))
            window.center()
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow = window
        }
    }

    @objc private func showGroupPicker() {
        if let window = groupPickerWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let hostingController = NSHostingController(rootView: GroupPickerView())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Select Groups"
            window.setContentSize(NSSize(width: 600, height: 700))
            window.center()
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            groupPickerWindow = window
        }
    }

    private func scheduleRefresh() {
        // Cancel existing timer
        refreshTimer?.invalidate()

        // Get refresh interval from settings (default 5 minutes)
        let intervalMinutes = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
        let interval = Double(intervalMinutes > 0 ? intervalMinutes : 5) * 60

        print("AppDelegate: Scheduling refresh every \(intervalMinutes) minutes")

        // Schedule new timer
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshGroups()
        }
    }

    private func refreshGroups() {
        print("AppDelegate: Refreshing groups")
        buildStatusItems()
    }

    @objc private func refreshGroupCountsFromMenu() {
        print("AppDelegate: Refreshing group counts from menu")

        // Refresh the counts for all selected groups
        Task {
            do {
                let token = try await JamfService.shared.getBearerToken()

                let selectedGroupIDs = Set((UserDefaults.standard.array(forKey: "selectedGroupIDs") as? [String]) ?? [])

                for selectedID in selectedGroupIDs {
                    let components = selectedID.split(separator: "-")
                    guard components.count == 2,
                          let groupID = Int(components[1]),
                          let groupType = String(components[0]) as String? else {
                        continue
                    }

                    // Find the menu item for this group
                    if let menu = mainMenu,
                       let item = menu.items.first(where: {
                           $0.title.contains(UserDefaults.standard.string(forKey: "groupDisplayName-\(groupID)") ?? "")
                       }) {

                        // Fetch the count
                        let count: Int
                        if groupType == "computer" {
                            count = try await GroupCounterService.shared.fetchComputerGroupCount(groupId: groupID, token: token)
                        } else {
                            count = try await GroupCounterService.shared.fetchMobileGroupCount(groupId: groupID, token: token)
                        }

                        DispatchQueue.main.async {
                            let displayName = UserDefaults.standard.string(forKey: "groupDisplayName-\(groupID)") ?? ""
                            item.title = "\(displayName) (\(count))"
                        }
                    }
                }
            } catch {
                print("Failed to refresh counts: \(error)")
            }
        }
    }
}
