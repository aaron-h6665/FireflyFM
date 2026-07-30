import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    var safeFilename: String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = components(separatedBy: invalid).joined(separator: "-").trimmed
        return cleaned.isEmpty ? "Attachment" : cleaned
    }

    var normalizedWebURLString: String? {
        guard let value = nilIfBlank else { return nil }
        let candidate = value.contains("://") ? value : "https://\(value)"
        guard let components = URLComponents(string: candidate),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host?.isEmpty == false else {
            return nil
        }
        return components.url?.absoluteString
    }
}

extension URL {
    static func validatedHTTPURL(from value: String) -> URL? {
        guard let url = URL(string: value.trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }
}

enum InitialsFormatter {
    static func initials(for name: String, fallback: String = "FF") -> String {
        let characters = name
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
        let value = String(characters).uppercased()
        return value.isEmpty ? fallback : value
    }
}

enum AsyncPhase: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)

    var isLoading: Bool { self == .loading }
}
