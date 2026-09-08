import Foundation
import Supabase
import Observation

struct ChildMedicalUpdate {
    let childId: UUID
    let allergies: String?
    let immunizationStatus: String?
    let physicalStatus: String?
    let medicalNotes: String?
    let medicineRequirements: String?
    let dietaryNotes: String?
    let emergencyNotes: String?
}

struct ChildGoalDraft {
    let schoolId: UUID
    let childId: UUID
    let title: String
    let notes: String?
}

struct ChildOverviewClient {
    var fetchGuardians: (UUID) async throws -> [ChildGuardian]
    var fetchProfiles: ([UUID]) async throws -> [UUID: UserProfile]
    var fetchMedicalProfile: (UUID) async throws -> ChildMedicalProfile?
    var fetchDocuments: (UUID) async throws -> [ChildDocument]
    var fetchMedicationInstructions: (UUID) async throws -> [MedicationInstruction]
    var fetchMedicationTasks: (UUID, UUID) async throws -> [MedicationTask]
    var saveMedicalProfile: (ChildMedicalUpdate) async throws -> Void
    var unlinkGuardian: (UUID, UUID) async throws -> Void
    var deactivateMember: (UUID, UUID) async throws -> Void

    var fetchEnrollmentReadiness: (UUID) async throws -> String = { childId in
        try await AppConstants.supabase.rpc("fetch_child_enrollment_readiness",
            params: ["input_child_id": childId.uuidString]).execute().value
    }

    static let live = ChildOverviewClient(
        fetchGuardians: { try await SchoolWorkflowService.shared.fetchChildGuardians(childId: $0) },
        fetchProfiles: { try await ProfileService.shared.fetchProfiles(ids: $0) },
        fetchMedicalProfile: { try await SchoolWorkflowService.shared.fetchChildMedicalProfile(childId: $0) },
        fetchDocuments: { try await SchoolWorkflowService.shared.fetchChildDocuments(childId: $0) },
        fetchMedicationInstructions: { try await SchoolWorkflowService.shared.fetchMedicationInstructions(childId: $0) },
        fetchMedicationTasks: {
            try await SchoolWorkflowService.shared.fetchMedicationTasks(schoolId: $0, childId: $1)
        },
        saveMedicalProfile: { update in
            try await SchoolWorkflowService.shared.saveChildMedicalProfile(
                childId: update.childId,
                allergies: update.allergies,
                immunizationStatus: update.immunizationStatus,
                physicalStatus: update.physicalStatus,
                medicalNotes: update.medicalNotes,
                medicationInstructions: nil,
                medicineRequirements: update.medicineRequirements,
                dietaryNotes: update.dietaryNotes,
                emergencyNotes: update.emergencyNotes
            )
        },
        unlinkGuardian: { try await SchoolWorkflowService.shared.unlinkChildGuardian(childId: $0, guardianId: $1) },
        deactivateMember: { try await SchoolWorkflowService.shared.deactivateSchoolMember(schoolId: $0, userId: $1) }
    )
}

@MainActor
@Observable
final class ChildOverviewModel {
    private let client: ChildOverviewClient
    private(set) var enrollmentReadiness: String?
    private(set) var guardians: [ChildGuardian] = []
    private(set) var guardianProfiles: [UUID: UserProfile] = [:]
    private(set) var medicalProfile: ChildMedicalProfile?
    private(set) var documents: [ChildDocument] = []
    private(set) var medicationInstructions: [MedicationInstruction] = []
    private(set) var medicationTasks: [MedicationTask] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: ChildOverviewClient) { self.client = client }

    func loadEnrollmentReadiness(childId: UUID) async {
        enrollmentReadiness = nil
        do { enrollmentReadiness = try await client.fetchEnrollmentReadiness(childId) }
        catch { enrollmentReadiness = "Readiness unavailable" }
    }

    func load(child: Child) async {
        phase = .loading
        errorMessage = nil
        do {
            async let guardians = client.fetchGuardians(child.id)
            async let medical = client.fetchMedicalProfile(child.id)
            async let documents = client.fetchDocuments(child.id)
            async let instructions = client.fetchMedicationInstructions(child.id)
            async let tasks = client.fetchMedicationTasks(child.schoolId, child.id)
            let loadedGuardians = try await guardians
            self.guardians = loadedGuardians
            medicalProfile = try await medical
            self.documents = try await documents
            medicationInstructions = try await instructions
            medicationTasks = try await tasks
            guardianProfiles = try await client.fetchProfiles(loadedGuardians.map(\.guardianId))
            phase = .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            phase = .idle
        } catch {
            errorMessage = AppErrorMessage.school("Could not load child overview", error)
            phase = .failed(errorMessage ?? "Could not load child overview")
        }
    }

    func refreshMedical(childId: UUID) async {
        do { medicalProfile = try await client.fetchMedicalProfile(childId) }
        catch where AppErrorMessage.isCancellation(error) { return }
        catch { errorMessage = AppErrorMessage.school("Could not refresh medical profile", error) }
    }

    func saveMedical(_ update: ChildMedicalUpdate) async throws {
        try await client.saveMedicalProfile(update)
        medicalProfile = try await client.fetchMedicalProfile(update.childId)
    }

    func unlinkGuardian(child: Child, guardian: ChildGuardian) async {
        do {
            try await client.unlinkGuardian(child.id, guardian.guardianId)
            await load(child: child)
        } catch {
            errorMessage = AppErrorMessage.school("Could not unlink guardian", error)
        }
    }

    func deactivateParent(child: Child, guardian: ChildGuardian) async {
        do {
            try await client.deactivateMember(child.schoolId, guardian.guardianId)
            try await client.unlinkGuardian(child.id, guardian.guardianId)
            await load(child: child)
        } catch {
            errorMessage = AppErrorMessage.school("Could not deactivate parent", error)
        }
    }
}

struct ChildRecordsClient {
    var fetchAttendance: (UUID, Date, Date) async throws -> [AttendanceSession]
    var fetchCareEvents: (UUID, UUID, Date, Date) async throws -> [ChildCareEvent]
    var fetchMedicationTasks: (UUID, UUID) async throws -> [MedicationTask]

    static let live = ChildRecordsClient(
        fetchAttendance: {
            try await SchoolOperationsService.shared.fetchAttendance(schoolId: $0, startDate: $1, endDate: $2)
        },
        fetchCareEvents: {
            try await SchoolOperationsService.shared.fetchCareEvents(schoolId: $0, start: $2, end: $3, childId: $1)
        },
        fetchMedicationTasks: {
            try await SchoolWorkflowService.shared.fetchMedicationTasks(schoolId: $0, childId: $1)
        }
    )
}

@MainActor
@Observable
final class ChildRecordsModel {
    private let client: ChildRecordsClient
    private(set) var attendance: [AttendanceSession] = []
    private(set) var careEvents: [ChildCareEvent] = []
    private(set) var medicationTasks: [MedicationTask] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: ChildRecordsClient) { self.client = client }

    func load(child: Child) async {
        phase = .loading
        errorMessage = nil
        let start = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        do {
            async let attendance = client.fetchAttendance(child.schoolId, start, Date())
            async let events = client.fetchCareEvents(child.schoolId, child.id, start, Date().addingTimeInterval(86_400))
            async let tasks = client.fetchMedicationTasks(child.schoolId, child.id)
            self.attendance = try await attendance.filter { $0.childId == child.id }
            careEvents = try await events
            medicationTasks = try await tasks
            phase = self.attendance.isEmpty && careEvents.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            phase = .idle
        } catch {
            errorMessage = AppErrorMessage.school("Could not load child records", error)
            phase = .failed(errorMessage ?? "Could not load child records")
        }
    }
}

struct ChildGoalsClient {
    var fetch: (UUID) async throws -> [ChildGoal]
    var create: (ChildGoalDraft) async throws -> Void

    static let live = ChildGoalsClient(
        fetch: { try await SchoolWorkflowService.shared.fetchChildGoals(childId: $0) },
        create: { draft in
            try await SchoolWorkflowService.shared.createChildGoal(
                schoolId: draft.schoolId,
                childId: draft.childId,
                title: draft.title,
                notes: draft.notes
            )
        }
    )
}

@MainActor
@Observable
final class ChildGoalsModel {
    private let client: ChildGoalsClient
    private(set) var goals: [ChildGoal] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: ChildGoalsClient) { self.client = client }

    func load(childId: UUID) async {
        phase = .loading
        errorMessage = nil
        do {
            goals = try await client.fetch(childId)
            phase = goals.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch {
            errorMessage = AppErrorMessage.school("Could not load child goals", error)
            phase = .failed(errorMessage ?? "Could not load child goals")
        }
    }

    func create(_ draft: ChildGoalDraft) async throws {
        try await client.create(draft)
        goals = try await client.fetch(draft.childId)
    }
}

struct ChildDocumentsClient {
    var fetch: (UUID) async throws -> [ChildDocument]
    var signedURL: (String) async throws -> URL

    static let live = ChildDocumentsClient(
        fetch: { try await SchoolWorkflowService.shared.fetchChildDocuments(childId: $0) },
        signedURL: { try await SchoolService.shared.signedPrivateFileURL(path: $0) }
    )
}

@MainActor
@Observable
final class ChildDocumentsModel {
    private let client: ChildDocumentsClient
    private(set) var documents: [ChildDocument] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: ChildDocumentsClient) { self.client = client }

    func load(childId: UUID) async {
        phase = .loading
        errorMessage = nil
        do {
            documents = try await client.fetch(childId)
            phase = documents.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch {
            errorMessage = AppErrorMessage.school("Could not load child documents", error)
            phase = .failed(errorMessage ?? "Could not load child documents")
        }
    }

    func signedURL(path: String) async throws -> URL {
        try await client.signedURL(path)
    }
}
