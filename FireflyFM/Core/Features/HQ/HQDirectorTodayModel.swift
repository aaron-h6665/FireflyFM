import Foundation
import Observation

struct HQDirectorTodayClient {
    var fetchSchools: () async throws -> [School]

    static let live = HQDirectorTodayClient(
        fetchSchools: { try await SchoolService.shared.fetchSchoolsForHQ() }
    )
}

@MainActor
@Observable
final class HQDirectorTodayModel {
    private let client: HQDirectorTodayClient
    private var requestId = UUID()

    private(set) var schools: [School] = []
    private(set) var phase: AsyncPhase = .idle

    init() {
        client = .live
    }

    init(client: HQDirectorTodayClient) {
        self.client = client
    }

    func load() async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        phase = schools.isEmpty ? .loading : .loaded

        do {
            let loaded = try await client.fetchSchools()
            guard requestId == currentRequestId else { return }
            schools = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            phase = loaded.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            guard requestId == currentRequestId else { return }
            phase = .failed(AppErrorMessage.school("Could not load the HQ summary", error))
        }
    }
}
