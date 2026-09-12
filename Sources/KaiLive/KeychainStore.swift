import Foundation
import Security

protocol KeychainStoring {
    func saveAPIKey(_ key: String) throws
    func readAPIKey() throws -> String?
    func deleteAPIKey() throws
}

struct KeychainStore: KeychainStoring {
    private let service = "com.sabajamalian.KaiLive"
    private let account = "openai-api-key"

    func saveAPIKey(_ key: String) throws {
        guard !key.isEmpty else {
            throw KeychainError.emptyKey
        }

        let data = Data(key.utf8)
        let query = baseQuery
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let attributes = [kSecValueData as String: data]
            try check(SecItemUpdate(query as CFDictionary, attributes as CFDictionary))
        } else if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    func readAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)

        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return key
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecItemNotFound {
            try check(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case emptyKey
    case invalidData
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            "Enter a non-empty API key."
        case .invalidData:
            "The saved API key could not be read."
        case let .status(status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain operation failed with status \(status)."
        }
    }
}
