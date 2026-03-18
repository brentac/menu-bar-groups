import Foundation

class GroupCounterService {
    static let shared = GroupCounterService()

    private init() {}

    func fetchComputerGroupCount(groupId: Int, token: String) async throws -> Int {
        var jamfURL = UserDefaults.standard.string(forKey: "jamfURL") ?? ""
        guard !jamfURL.isEmpty else {
            throw JamfServiceError.missingCredentials
        }

        if !jamfURL.hasPrefix("http://") && !jamfURL.hasPrefix("https://") {
            jamfURL = "https://\(jamfURL)"
        }

        let urlString = "\(jamfURL)/JSSResource/computergroups/id/\(groupId)"
        guard let url = URL(string: urlString) else {
            throw JamfServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw JamfServiceError.fetchFailed
        }

        return try parseGroupCount(data)
    }

    func fetchMobileGroupCount(groupId: Int, token: String) async throws -> Int {
        var jamfURL = UserDefaults.standard.string(forKey: "jamfURL") ?? ""
        guard !jamfURL.isEmpty else {
            throw JamfServiceError.missingCredentials
        }

        if !jamfURL.hasPrefix("http://") && !jamfURL.hasPrefix("https://") {
            jamfURL = "https://\(jamfURL)"
        }

        let urlString = "\(jamfURL)/JSSResource/mobiledevicegroups/id/\(groupId)"
        guard let url = URL(string: urlString) else {
            throw JamfServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw JamfServiceError.fetchFailed
        }

        return try parseGroupCount(data)
    }

    private func parseGroupCount(_ data: Data) throws -> Int {
        if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Handle both computer_group and mobile_device_group responses
            if let groupDict = dict["computer_group"] as? [String: Any] ?? dict["mobile_device_group"] as? [String: Any] {
                if let computers = groupDict["computers"] as? [[String: Any]] {
                    return computers.count
                }
                if let mobileDevices = groupDict["mobile_devices"] as? [[String: Any]] {
                    return mobileDevices.count
                }
            }
        }
        return 0
    }
}
