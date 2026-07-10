import Foundation
import Security

struct KeychainAPIKeyStore: APIKeyStoring {
    private let service = "app.cryptolens.coingecko"
    private let account = "demo-api-key"

    func loadDemoKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    func saveDemoKey(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func deleteDemoKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }
}

struct KeychainError: LocalizedError, Equatable, Sendable {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}

struct DevelopmentAPIKeyStore: APIKeyStoring {
    private let keychain: KeychainAPIKeyStore
    private let debugFallback: String?

    init(keychain: KeychainAPIKeyStore = KeychainAPIKeyStore()) {
        self.keychain = keychain
#if DEBUG
        debugFallback = ProcessInfo.processInfo.environment["COINGECKO_DEMO_API_KEY"]
#else
        debugFallback = nil
#endif
    }

    func loadDemoKey() throws -> String? {
        try keychain.loadDemoKey() ?? debugFallback
    }

    func saveDemoKey(_ key: String) throws {
        try keychain.saveDemoKey(key)
    }

    func deleteDemoKey() throws {
        try keychain.deleteDemoKey()
    }
}
