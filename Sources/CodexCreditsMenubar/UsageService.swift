import Foundation

enum UsageServiceError: LocalizedError {
    case unreadableAuth
    case invalidAuth
    case missingToken
    case endpoint(statusCode: Int?)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unreadableAuth: return "Codex authentication is unavailable."
        case .invalidAuth: return "Codex authentication is invalid."
        case .missingToken: return "Codex authentication has no access token."
        case .endpoint: return "Usage endpoint is unavailable."
        case .malformedResponse: return "Usage data could not be read."
        }
    }
}

struct UsageService {
    let configuration: RequestConfiguration
    let session: URLSession

    init(configuration: RequestConfiguration = RequestConfiguration(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func fetchSpendControl() async throws -> SpendControl {
        let auth = try loadAuth()
        var request = URLRequest(url: configuration.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexCreditsMenubar", forHTTPHeaderField: "User-Agent")
        if let accountID = auth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Deliberately do not retain the underlying request or response details.
            throw UsageServiceError.endpoint(statusCode: nil)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UsageServiceError.endpoint(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        return try Self.parseSpendControl(data)
    }

    /// Injectable parser seam for endpoint-contract fixtures.  It accepts only
    /// response bytes and returns a minimized domain value; callers never retain
    /// raw response data.
    static func parseSpendControl(_ data: Data) throws -> SpendControl {
        do {
            guard let spendControl = try JSONDecoder().decode(UsageResponse.self, from: data).spendControl else {
                throw UsageServiceError.malformedResponse
            }
            return spendControl
        } catch let error as UsageServiceError {
            throw error
        } catch {
            throw UsageServiceError.malformedResponse
        }
    }

    private func loadAuth() throws -> AuthFile {
        guard let data = try? Data(contentsOf: configuration.authFileURL) else { throw UsageServiceError.unreadableAuth }
        guard let auth = try? JSONDecoder().decode(AuthFile.self, from: data) else { throw UsageServiceError.invalidAuth }
        guard !auth.accessToken.isEmpty else { throw UsageServiceError.missingToken }
        return auth
    }
}

private struct AuthFile: Decodable {
    let accessToken: String
    let accountID: String?

    enum CodingKeys: String, CodingKey { case tokens }
    enum TokenKeys: String, CodingKey { case accessToken = "access_token", accessTokenCamel = "accessToken", accountID = "account_id", accountIDCamel = "accountId" }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        let tokens = try root.nestedContainer(keyedBy: TokenKeys.self, forKey: .tokens)
        accessToken = try tokens.decodeIfPresent(String.self, forKey: .accessToken)
            ?? tokens.decodeIfPresent(String.self, forKey: .accessTokenCamel) ?? ""
        accountID = try tokens.decodeIfPresent(String.self, forKey: .accountID)
            ?? tokens.decodeIfPresent(String.self, forKey: .accountIDCamel)
    }
}
