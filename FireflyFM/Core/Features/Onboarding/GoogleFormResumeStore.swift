import Foundation
import Security

enum GoogleFormRecipientPresentation {
    static func canOpen(status: String?) -> Bool {
        !["approved", "pending_review", "ambiguous", "error"].contains(status ?? "")
    }

    static let draftHelp = "To save unfinished answers, sign in to Google inside the Form and check that saving is enabled. Return using the same Google account. FireflyFM saves your checklist; Google saves Form drafts."
}

/// Retains only the short-lived launch link, never the recipient's answers.
/// Scoped to backend, signed-in user, and Form; logout does not erase another
/// account's entry or expose it to the next user. Expired entries are discarded.
struct GoogleFormResumeStore {
    var read: (String) -> Data? = { account in
        var query = keychainQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
    var write: (String, Data?) -> Void = { account, data in
        let query = keychainQuery(account)
        guard let data else { SecItemDelete(query as CFDictionary); return }
        let attributes = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func key(backend: String, userId: UUID, connectionId: UUID) -> String {
        "\(backend)|\(userId.uuidString)|\(connectionId.uuidString)"
    }

    func token(for key: String, now: Date = Date()) -> String? {
        guard let data = read(key) else { return nil }
        guard let launch = try? JSONDecoder().decode(GoogleFormSubmissionLaunch.self, from: data),
              launch.expiresAt > now,
              let parts = URLComponents(string: launch.launchURL),
              parts.scheme == "https", parts.host == "docs.google.com",
              let token = parts.queryItems?.first(where: { $0.name.hasPrefix("entry.") })?.value,
              token.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            write(key, nil)
            return nil
        }
        return token
    }

    func save(_ launch: GoogleFormSubmissionLaunch, for key: String) {
        write(key, try? JSONEncoder().encode(launch))
    }

    private static func keychainQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "FireflyFM.google-form-resume",
         kSecAttrAccount as String: account]
    }
}
