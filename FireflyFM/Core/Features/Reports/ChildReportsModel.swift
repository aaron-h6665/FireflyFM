import Foundation
import Observation

struct ChildReportsClient {
    var fetch: (UUID) async throws -> [ChildProgressReport]

    static let live = ChildReportsClient(
        fetch: { try await SchoolWorkflowService.shared.fetchChildProgressReports(childId: $0) }
    )
}

@MainActor
@Observable
final class ChildReportsModel {
    private let client: ChildReportsClient
    private(set) var reports: [ChildProgressReport] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: ChildReportsClient) { self.client = client }

    func load(childId: UUID) async {
        phase = .loading
        errorMessage = nil
        do {
            reports = try await client.fetch(childId)
            phase = reports.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch {
            errorMessage = AppErrorMessage.school("Could not load progress reports", error)
            phase = .failed(errorMessage ?? "Could not load progress reports")
        }
    }
}
