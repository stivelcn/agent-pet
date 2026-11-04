import Foundation
import Security
import AgentPetCore

struct PetRelayCredentials: Codable, Sendable, Equatable {
    let deviceID: String
    let token: String
}

enum PetRelayError: Error, LocalizedError {
    case server(String)
    case storage
    case credentials
    var errorDescription: String? {
        let key: String
        switch self {
        case .storage: key = "Pet messages could not be saved. No unread message was acknowledged."
        case .credentials: key = "The pairing credential could not be read or saved in Keychain."
        case .server(let code):
            key = switch code {
            case "invalid_code": "Enter a 6-character code containing letters and digits."
            case "invite_unavailable": "This pairing code has expired or is unavailable."
            case "already_paired": "This device is already paired."
            case "cancel_invitation_first": "Cancel the current invitation before joining another."
            case "invalid_text": "Use 1–20 characters, without line breaks."
            case "rate_limited": "Too many attempts. Please try again later."
            case "inbox_full": "Your friend's unread inbox is full. Please wait for them to respond."
            case "not_paired": "This pairing is no longer active. The message was not sent to anyone else."
            case "unauthorized": "The server did not accept this device's pairing credential."
            default: "The message relay is temporarily unavailable. Your unread messages are safe."
            }
        }
        return NSLocalizedString(key, comment: "pet relay error")
    }
}

@MainActor
protocol PetRelayCredentialStore {
    func load() throws -> PetRelayCredentials?
    func save(_ credentials: PetRelayCredentials) throws
}

@MainActor
final class PetRelayKeychain: PetRelayCredentialStore {
    private let service: String
    init(endpoint: URL, namespace: String = LocalConfiguration.preferencesSuite) {
        // Explicit preferences suites (including UI QA) own independent credentials.
        service = namespace + ".relay." + endpoint.absoluteString
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "installation", kSecAttrSynchronizable as String: false]
    }
    func load() throws -> PetRelayCredentials? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let credential = try? JSONDecoder().decode(PetRelayCredentials.self, from: data) else {
            throw PetRelayError.credentials
        }
        return credential
    }
    func save(_ credentials: PetRelayCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess else {
                throw PetRelayError.credentials
            }
        } else if status != errSecSuccess { throw PetRelayError.credentials }
    }
}

protocol PetRelayTransport: Sendable {
    func register(name: String) async throws -> PetRelayCredentials
    func fetch(_ path: String, token: String, body: Data?) async throws -> PetRelaySnapshot
    func watch(token: String, changed: @escaping @Sendable () async -> Void) async throws
}

struct PetRelayAPI: PetRelayTransport {
    static let endpoint = URL(string: "https://imagepro.ycgod.online/agentpet-relay/")!
    let baseURL: URL
    let session: URLSession
    init(baseURL: URL = Self.endpoint, session: URLSession = .shared) { self.baseURL = baseURL; self.session = session }

    /// appendingPathComponent retains the relay prefix (URL(string:relativeTo:) with / would drop it).
    func url(_ path: String) -> URL { baseURL.appendingPathComponent(path) }
    private func request(_ path: String, token: String?, body: Data?) async throws -> Data {
        var request = URLRequest(url: url(path))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            struct Failure: Decodable { var error: String }
            let code = (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "unavailable"
            throw PetRelayError.server(code)
        }
        return data
    }
    func register(name: String) async throws -> PetRelayCredentials {
        let body = try JSONEncoder().encode(["name": name])
        return try JSONDecoder().decode(PetRelayCredentials.self, from: await request("v1/devices", token: nil, body: body))
    }
    func fetch(_ path: String, token: String, body: Data? = nil) async throws -> PetRelaySnapshot {
        try JSONDecoder().decode(PetRelaySnapshot.self, from: await request(path, token: token, body: body))
    }
    func watch(token: String, changed: @escaping @Sendable () async -> Void) async throws {
        var components = URLComponents(url: url("v1/events"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        socket.resume()
        try await withTaskCancellationHandler {
            defer { socket.cancel(with: .goingAway, reason: nil) }
            while !Task.isCancelled {
                _ = try await socket.receive()
                await changed()
            }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }
}
