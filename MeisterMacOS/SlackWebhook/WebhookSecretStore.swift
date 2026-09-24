import Foundation
import Security

/// Keeps the complete webhook URL (including its secret) out of preferences.
enum WebhookSecretStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "meister.slack.webhook",
         kSecAttrAccount as String: "incoming-webhook"]
    }

    enum StoreError: LocalizedError {
        case invalidURL, invalidData, keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Gültige Slack-HTTPS-URL erforderlich."
            case .invalidData: return "Webhook im Schlüsselbund ist ungültig."
            case .keychain(let status): return "Schlüsselbund-Zugriff fehlgeschlagen (\(status))."
            }
        }
    }

    static func validURL(_ value: String) -> URL? {
        // Match raw input: no URL normalization, encoded separators, credentials,
        // alternative ports, queries or fragments may hide a different endpoint.
        let pattern = #"\Ahttps://hooks\.slack\.com/services/T[A-Za-z0-9]*/B[A-Za-z0-9]*/[A-Za-z0-9_-]+\z"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return URL(string: value)
    }

    static func save(_ value: String) throws {
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw StoreError.keychain(status)
            }
            return
        }
        guard validURL(value) != nil else { throw StoreError.invalidURL }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    static func load() throws -> String {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8), validURL(value) != nil else {
            throw StoreError.invalidData
        }
        return value
    }
}

/// Never forward the webhook payload to a redirect destination, even on Slack.
final class WebhookSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
