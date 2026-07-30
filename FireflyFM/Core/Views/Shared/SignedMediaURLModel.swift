import Foundation
import Observation

struct SignedMediaClient {
    var resolve: (String) async throws -> URL

    static let live = SignedMediaClient(
        resolve: { try await SchoolService.shared.signedPrivateFileURL(path: $0) }
    )
}

@MainActor
@Observable
final class SignedMediaURLModel {
    private let client: SignedMediaClient
    private(set) var url: URL?
    private(set) var phase: AsyncPhase = .idle

    init() { client = .live }
    init(client: SignedMediaClient) { self.client = client }

    func load(path: String) async {
        phase = .loading
        do {
            url = try await client.resolve(path)
            phase = .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch { phase = .failed(AppErrorMessage.school("Could not load media", error)) }
    }
}
