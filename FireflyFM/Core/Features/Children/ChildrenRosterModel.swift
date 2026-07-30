import Foundation
import Observation

enum ChildrenRosterScope: Equatable {
    case school(UUID)
    case allSchools
}

struct ChildrenRosterClient {
    var fetchSchools: () async throws -> [School]
    var fetchAllChildren: () async throws -> [Child]
    var fetchChildren: (UUID) async throws -> [Child]

    static let live = ChildrenRosterClient(
        fetchSchools: { try await SchoolService.shared.fetchSchoolsForHQ() },
        fetchAllChildren: { try await SchoolWorkflowService.shared.fetchAllChildrenForHQ() },
        fetchChildren: { try await SchoolWorkflowService.shared.fetchChildren(schoolId: $0) }
    )
}

@MainActor
@Observable
final class ChildrenRosterModel {
    private let client: ChildrenRosterClient
    private var requestId = UUID()

    private(set) var schools: [School] = []
    private(set) var children: [Child] = []
    private(set) var phase: AsyncPhase = .idle

    init() {
        client = .live
    }

    init(client: ChildrenRosterClient) {
        self.client = client
    }

    func load(scope: ChildrenRosterScope) async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        phase = children.isEmpty ? .loading : .loaded

        do {
            let loadedSchools: [School]
            let loadedChildren: [Child]
            switch scope {
            case .school(let schoolId):
                loadedSchools = []
                loadedChildren = try await client.fetchChildren(schoolId)
            case .allSchools:
                async let schools = client.fetchSchools()
                async let children = client.fetchAllChildren()
                (loadedSchools, loadedChildren) = try await (schools, children)
            }
            guard requestId == currentRequestId else { return }
            schools = loadedSchools
            children = loadedChildren
            phase = loadedChildren.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            guard requestId == currentRequestId else { return }
            phase = .failed(AppErrorMessage.school("Could not load children", error))
        }
    }
}
