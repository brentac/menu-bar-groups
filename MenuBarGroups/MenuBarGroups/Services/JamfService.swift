import Foundation

class JamfService {
    static let shared = JamfService()

    private(set) var cachedToken: String?
    private(set) var tokenExpiresAt: Date?

    private init() {}

    func getBearerToken() async throws -> String {
        // Return cached token if still valid
        if let token = cachedToken, let expiresAt = tokenExpiresAt, Date() < expiresAt {
            return token
        }

        var jamfURL = UserDefaults.standard.string(forKey: "jamfURL") ?? ""
        let clientID = UserDefaults.standard.string(forKey: "clientID") ?? ""
        let clientSecret = try KeychainService.shared.read(account: "clientSecret") ?? ""

        guard !jamfURL.isEmpty, !clientID.isEmpty, !clientSecret.isEmpty else {
            throw JamfServiceError.missingCredentials
        }

        // Ensure URL has protocol
        if !jamfURL.hasPrefix("http://") && !jamfURL.hasPrefix("https://") {
            jamfURL = "https://\(jamfURL)"
        }

        let urlString = "\(jamfURL)/api/oauth/token"
        print("JamfService: Requesting token from: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("JamfService: Invalid URL: \(urlString)")
            throw JamfServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyComponents = [
            "grant_type=client_credentials",
            "client_id=\(clientID)",
            "client_secret=\(clientSecret)"
        ]
        let bodyString = bodyComponents.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        print("JamfService: Request URL: \(request.url?.absoluteString ?? "nil")")
        print("JamfService: Request body: grant_type=client_credentials&client_id=\(clientID)&client_secret=[REDACTED]")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("JamfService: Network error: \(error.localizedDescription)")
            throw JamfServiceError.authenticationFailed
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("JamfService: Authentication failed with status \(statusCode)")
            if let responseText = String(data: data, encoding: .utf8) {
                print("JamfService: Response: \(responseText)")
            }
            throw JamfServiceError.authenticationFailed
        }

        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(TokenResponse.self, from: data)

        cachedToken = tokenResponse.accessToken
        tokenExpiresAt = Date().addingTimeInterval(Double(tokenResponse.expiresIn) - 60) // Refresh 60s before expiry

        return tokenResponse.accessToken
    }

    func fetchComputerGroups(token: String) async throws -> [JamfGroup] {
        var jamfURL = UserDefaults.standard.string(forKey: "jamfURL") ?? ""
        guard !jamfURL.isEmpty else {
            throw JamfServiceError.missingCredentials
        }

        // Ensure URL has protocol
        if !jamfURL.hasPrefix("http://") && !jamfURL.hasPrefix("https://") {
            jamfURL = "https://\(jamfURL)"
        }

        let urlString = "\(jamfURL)/JSSResource/computergroups"
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

        return try parseComputerGroups(data)
    }

    func fetchMobileDeviceGroups(token: String) async throws -> [JamfGroup] {
        var jamfURL = UserDefaults.standard.string(forKey: "jamfURL") ?? ""
        guard !jamfURL.isEmpty else {
            throw JamfServiceError.missingCredentials
        }

        // Ensure URL has protocol
        if !jamfURL.hasPrefix("http://") && !jamfURL.hasPrefix("https://") {
            jamfURL = "https://\(jamfURL)"
        }

        let urlString = "\(jamfURL)/JSSResource/mobiledevicegroups"
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

        return try parseMobileDeviceGroups(data)
    }

    private func parseComputerGroups(_ data: Data) throws -> [JamfGroup] {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groupsArray = dict["computer_groups"] as? [[String: Any]] else {
            throw JamfServiceError.fetchFailed
        }

        var groups: [JamfGroup] = []
        for groupDict in groupsArray {
            if let id = groupDict["id"] as? NSNumber,
               let name = groupDict["name"] as? String {
                let group = JamfGroup(id: id.intValue, name: name, memberCount: 0, type: .computer)
                groups.append(group)
            }
        }
        return groups.sorted { $0.name < $1.name }
    }

    private func parseMobileDeviceGroups(_ data: Data) throws -> [JamfGroup] {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groupsArray = dict["mobile_device_groups"] as? [[String: Any]] else {
            throw JamfServiceError.fetchFailed
        }

        var groups: [JamfGroup] = []
        for groupDict in groupsArray {
            if let id = groupDict["id"] as? NSNumber,
               let name = groupDict["name"] as? String {
                let group = JamfGroup(id: id.intValue, name: name, memberCount: 0, type: .mobile)
                groups.append(group)
            }
        }
        return groups.sorted { $0.name < $1.name }
    }

    func clearToken() {
        cachedToken = nil
        tokenExpiresAt = nil
    }
}

// MARK: - Response Models

private struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

enum JamfServiceError: Error, LocalizedError {
    case missingCredentials
    case invalidURL
    case authenticationFailed
    case fetchFailed

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing Jamf credentials"
        case .invalidURL:
            return "Invalid Jamf URL"
        case .authenticationFailed:
            return "Failed to authenticate with Jamf Pro"
        case .fetchFailed:
            return "Failed to fetch groups from Jamf Pro"
        }
    }
}
