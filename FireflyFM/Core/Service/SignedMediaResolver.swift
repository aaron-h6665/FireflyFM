import Foundation
import Supabase

actor SignedMediaResolver {
    static let shared = SignedMediaResolver()

    private struct CacheEntry {
        let url: URL
        let expiresAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let lifetime: TimeInterval = 5 * 60

    func url(bucket: String, path: String) async throws -> URL {
        let key = "\(bucket)/\(path)"
        if let entry = cache[key], entry.expiresAt.timeIntervalSinceNow > 30 {
            return entry.url
        }

        let url = try await AppConstants.supabase.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: Int(lifetime))
        cache[key] = CacheEntry(url: url, expiresAt: Date().addingTimeInterval(lifetime))
        return url
    }

    func resolve(bucket: String, path: String?, legacyURL: String?) async -> String? {
        if let path, path.isEmpty == false,
           let url = try? await url(bucket: bucket, path: path) {
            return url.absoluteString
        }
        return legacyURL
    }

    func clear() {
        cache.removeAll()
    }
}
