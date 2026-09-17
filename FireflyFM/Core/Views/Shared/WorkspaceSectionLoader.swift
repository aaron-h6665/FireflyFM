import Foundation
import Observation

struct WorkspaceLoadScope: Hashable {
    let userId: UUID?
    let membershipId: UUID?
    let schoolId: UUID?
}

/// Each section commits independently. A superseded response cannot publish
/// values, errors, or loading state into a newer request or another workspace.
@MainActor
@Observable
final class WorkspaceSectionLoader<Section: Hashable, Value> {
    private(set) var scope: WorkspaceLoadScope?
    private(set) var values: [Section: Value] = [:]
    private(set) var errors: [Section: String] = [:]
    private(set) var loading: Set<Section> = []
    private var requests: [Section: UUID] = [:]

    func reset(to scope: WorkspaceLoadScope) {
        guard self.scope != scope else { return }
        self.scope = scope
        values = [:]
        errors = [:]
        loading = []
        requests = [:]
    }

    func load(_ section: Section, scope: WorkspaceLoadScope, failureMessage: String,
              operation: () async throws -> Value) async {
        guard !Task.isCancelled else { return }
        reset(to: scope)
        let request = UUID()
        requests[section] = request
        errors[section] = nil
        loading.insert(section)
        defer {
            if self.scope == scope && requests[section] == request {
                loading.remove(section)
            }
        }
        do {
            let value = try await operation()
            guard self.scope == scope, requests[section] == request, !Task.isCancelled else { return }
            values[section] = value
        } catch {
            guard self.scope == scope, requests[section] == request, !Task.isCancelled,
                  !AppErrorMessage.isCancellation(error) else { return }
            errors[section] = AppErrorMessage.school(failureMessage, error)
        }
    }
}
