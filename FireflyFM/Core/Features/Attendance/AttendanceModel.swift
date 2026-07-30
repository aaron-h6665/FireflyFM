import Foundation
import Observation

struct AttendanceScope: Equatable {
    let schoolId: UUID?
    let includesAllSchools: Bool
    let startDate: Date
    let endDate: Date
}

struct AttendanceCorrection {
    let sessionId: UUID
    let checkedInAt: Date?
    let checkedOutAt: Date?
    let state: AttendanceState
    let notes: String
    let reason: String
}

struct AttendanceClient {
    var fetchAllChildren: () async throws -> [Child]
    var fetchChildren: (UUID) async throws -> [Child]
    var fetchSchools: () async throws -> [School]
    var fetchAllSessions: (Date, Date) async throws -> [AttendanceSession]
    var fetchSessions: (UUID, Date, Date) async throws -> [AttendanceSession]
    var recordBatch: ([UUID], AttendanceAction) async throws -> [AttendanceBatchResult]
    var correct: (AttendanceCorrection) async throws -> AttendanceSession

    static let live = AttendanceClient(
        fetchAllChildren: { try await SchoolWorkflowService.shared.fetchAllChildrenForHQ() },
        fetchChildren: { try await SchoolWorkflowService.shared.fetchChildren(schoolId: $0) },
        fetchSchools: { try await SchoolService.shared.fetchSchoolsForHQ() },
        fetchAllSessions: {
            try await SchoolOperationsService.shared.fetchAttendanceForHQ(startDate: $0, endDate: $1)
        },
        fetchSessions: {
            try await SchoolOperationsService.shared.fetchAttendance(schoolId: $0, startDate: $1, endDate: $2)
        },
        recordBatch: {
            try await SchoolOperationsService.shared.recordAttendanceBatch(childIds: $0, action: $1)
        },
        correct: { correction in
            try await SchoolOperationsService.shared.correctAttendance(
                sessionId: correction.sessionId,
                checkedInAt: correction.checkedInAt,
                checkedOutAt: correction.checkedOutAt,
                state: correction.state,
                notes: correction.notes,
                reason: correction.reason
            )
        }
    )
}

@MainActor
@Observable
final class AttendanceModel {
    private let client: AttendanceClient
    private var requestId = UUID()
    private var scope: AttendanceScope?

    private(set) var children: [Child] = []
    private(set) var schools: [School] = []
    private(set) var sessions: [AttendanceSession] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?
    private(set) var isRecordingBatch = false

    init() {
        client = .live
    }

    init(client: AttendanceClient) {
        self.client = client
    }

    func load(scope: AttendanceScope) async {
        self.scope = scope
        let currentRequestId = UUID()
        requestId = currentRequestId
        phase = .loading
        errorMessage = nil

        do {
            let loadedChildren: [Child]
            let loadedSessions: [AttendanceSession]
            let loadedSchools: [School]
            if scope.includesAllSchools {
                async let children = client.fetchAllChildren()
                async let sessions = client.fetchAllSessions(scope.startDate, scope.endDate)
                async let schools = client.fetchSchools()
                (loadedChildren, loadedSessions, loadedSchools) = try await (children, sessions, schools)
            } else if let schoolId = scope.schoolId {
                async let children = client.fetchChildren(schoolId)
                async let sessions = client.fetchSessions(schoolId, scope.startDate, scope.endDate)
                (loadedChildren, loadedSessions) = try await (children, sessions)
                loadedSchools = []
            } else {
                loadedChildren = []
                loadedSessions = []
                loadedSchools = []
            }

            guard requestId == currentRequestId else { return }
            children = loadedChildren
            sessions = loadedSessions
            schools = loadedSchools
            phase = loadedChildren.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            guard requestId == currentRequestId else { return }
            phase = .idle
        } catch {
            guard requestId == currentRequestId else { return }
            errorMessage = AppErrorMessage.school("Could not load attendance", error)
            phase = .failed(errorMessage ?? "Could not load attendance")
        }
    }

    func recordBatch(childIds: [UUID], action: AttendanceAction) async -> [AttendanceBatchResult]? {
        guard childIds.isEmpty == false else { return [] }
        isRecordingBatch = true
        errorMessage = nil
        defer { isRecordingBatch = false }
        do {
            let results = try await client.recordBatch(childIds, action)
            if let scope { await load(scope: scope) }
            return results
        } catch {
            errorMessage = AppErrorMessage.school("Could not update attendance", error)
            return nil
        }
    }

    func correct(_ correction: AttendanceCorrection) async throws {
        _ = try await client.correct(correction)
    }

    func showError(_ message: String) {
        errorMessage = message
    }
}
