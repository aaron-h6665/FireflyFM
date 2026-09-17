import Foundation

/// Coarse capabilities supplied by a school membership. Resource-specific
/// policies add ownership, school, child, and room context before authorizing
/// an action.
enum SchoolCapability: String, CaseIterable, Hashable {
    case useAccessChecklist
    case requestChildConnection
    case manageChildConnections
    case editChildIdentity
    case editChildSchoolRecords
    case manageChildGuardians
    case generateChildAISummary
    case recordAttendance
    case correctAttendance
    case viewCrossSchoolAttendance
    case manageAttendanceCodes
    case recordCare
    case createFamilyRequest
    case handleFamilyRequests
    case createAssignments
    case reviewAssignments
    case viewPaperwork
    case createPaperwork
    case reviewPaperwork
    case manageEvents
    case composeCommunity
    case manageNewsletters
    case createSchoolChats
    case overseeSchoolChats
    case leaveNonSystemChats
    case composeSchoolNotifications
    case manageMemberOnboarding
    case manageDirectorOnboarding
    case manageSchools
    case viewCrossSchoolData
    case viewBilling
    case payInvoices
    case manageSchoolBilling
    case viewCrossSchoolBilling
    case createHQChats
    case manageHQChats
}

extension SchoolRole {
    /// Stable defaults only. Feature policies must still account for resource
    /// ownership and scope; this set is not a security boundary.
    var baseCapabilities: Set<SchoolCapability> {
        switch self {
        case .parent:
            [
                .useAccessChecklist,
                .requestChildConnection,
                .createFamilyRequest,
                .viewPaperwork,
                .viewBilling,
                .payInvoices,
                .leaveNonSystemChats
            ]
        case .teacher:
            [
                .useAccessChecklist,
                .editChildSchoolRecords,
                .recordAttendance,
                .recordCare,
                .handleFamilyRequests,
                .viewPaperwork,
                .viewBilling,
                .payInvoices,
                .manageEvents,
                .composeCommunity,
                .leaveNonSystemChats
            ]
        case .schoolDirector:
            [
                .useAccessChecklist,
                .manageChildConnections,
                .editChildIdentity,
                .editChildSchoolRecords,
                .manageChildGuardians,
                .generateChildAISummary,
                .recordAttendance,
                .correctAttendance,
                .manageAttendanceCodes,
                .recordCare,
                .handleFamilyRequests,
                .createAssignments,
                .reviewAssignments,
                .viewPaperwork,
                .createPaperwork,
                .reviewPaperwork,
                .manageEvents,
                .composeCommunity,
                .manageNewsletters,
                .overseeSchoolChats,
                .composeSchoolNotifications,
                .manageMemberOnboarding,
                .viewBilling,
                .manageSchoolBilling
            ]
        case .hqDirector:
            [
                .manageChildConnections,
                .editChildIdentity,
                .editChildSchoolRecords,
                .manageChildGuardians,
                .viewCrossSchoolAttendance,
                .correctAttendance,
                .manageAttendanceCodes,
                .recordCare,
                .createAssignments,
                .reviewAssignments,
                .viewPaperwork,
                .createPaperwork,
                .reviewPaperwork,
                .manageEvents,
                .composeCommunity,
                .manageDirectorOnboarding,
                .manageSchools,
                .viewCrossSchoolData,
                .viewBilling,
                .viewCrossSchoolBilling,
                .manageSchoolBilling,
                .createHQChats,
                .manageHQChats
            ]
        }
    }

    func has(_ capability: SchoolCapability) -> Bool {
        baseCapabilities.contains(capability)
    }

    var usesAccessChecklist: Bool { has(.useAccessChecklist) }
}

/// The portion of session state that feature policies need. Keeping this a
/// value type makes policy decisions deterministic and unit-testable.
struct AppAccessContext: Hashable {
    let userId: UUID?
    let membershipId: UUID?
    let role: SchoolRole?
    let activeSchoolId: UUID?
    let selectedSchoolId: UUID?
    let accessState: String

    init(
        userId: UUID? = nil,
        membershipId: UUID? = nil,
        role: SchoolRole?,
        activeSchoolId: UUID? = nil,
        selectedSchoolId: UUID? = nil,
        accessState: String = "full"
    ) {
        self.userId = userId
        self.membershipId = membershipId
        self.role = role
        self.activeSchoolId = activeSchoolId
        self.selectedSchoolId = selectedSchoolId
        self.accessState = accessState
    }

    var effectiveSchoolId: UUID? { selectedSchoolId ?? activeSchoolId }

    func has(_ capability: SchoolCapability) -> Bool {
        let management: Set<SchoolCapability> = [.createAssignments, .reviewAssignments, .createPaperwork, .reviewPaperwork, .manageSchoolBilling, .viewCrossSchoolBilling]
        if management.contains(capability) && accessState != "full" { return false }
        return role?.has(capability) == true
    }

    func isInSchool(_ schoolId: UUID) -> Bool {
        effectiveSchoolId == schoolId || has(.viewCrossSchoolData)
    }
}

extension AppSessionManager {
    func accessContext(selectedSchoolId: UUID? = nil) -> AppAccessContext {
        AppAccessContext(
            userId: profile?.id,
            membershipId: activeMembershipId,
            role: role,
            activeSchoolId: activeSchool?.id,
            selectedSchoolId: selectedSchoolId,
            accessState: activeContext?.membership.accessState ?? "onboarding"
        )
    }
}

struct ChatAccessPolicy {
    let context: AppAccessContext

    var canCreateSchoolRoom: Bool { context.has(.createSchoolChats) }
    var canOverseeSchoolRooms: Bool { context.has(.overseeSchoolChats) }
    var canCreateHQRoom: Bool { context.has(.createHQChats) }
    var canManageHQRoom: Bool { context.has(.manageHQChats) }
    var canCreateAnyRoom: Bool { canCreateSchoolRoom || canCreateHQRoom }

    func canManage(room: ChatRoom) -> Bool {
        if room.isHQCustomRoom {
            return canManageHQRoom && room.systemManaged == false
        }
        return canOverseeSchoolRooms && room.systemManaged == false
    }

    func canLeave(room: ChatRoom) -> Bool {
        context.has(.leaveNonSystemChats) && room.systemManaged == false
    }
}

struct ChatRoomCapabilities: Equatable {
    let canCreateFamilyRequest: Bool
    let canRecordCare: Bool
    let canCallGuardians: Bool
    let canLabelAnyActivity: Bool
    let canHandleFamilyRequest: Bool
}

struct ChatRoomInteractionPolicy {
    let context: AppAccessContext
    let room: ChatRoom

    var capabilities: ChatRoomCapabilities {
        ChatRoomCapabilities(
            canCreateFamilyRequest: room.isChildFamilyRoom && context.has(.createFamilyRequest),
            canRecordCare: room.isChildFamilyRoom && context.has(.recordCare),
            canCallGuardians: room.isChildFamilyRoom && context.has(.recordCare),
            canLabelAnyActivity: context.has(.overseeSchoolChats),
            canHandleFamilyRequest: context.has(.handleFamilyRequests)
        )
    }
}

struct ChildAccessPolicy {
    let context: AppAccessContext
    var canViewEnrollmentReadiness: Bool { context.role == .teacher }

    var canRequestConnection: Bool { context.has(.requestChildConnection) }
    var canManageConnections: Bool { context.has(.manageChildConnections) }
    var canEditIdentity: Bool { context.has(.editChildIdentity) }
    var canEditSchoolRecords: Bool { context.has(.editChildSchoolRecords) }
    var canManageGuardians: Bool { context.has(.manageChildGuardians) }
    var canGenerateAISummary: Bool { context.has(.generateChildAISummary) }
    var isFamilyMember: Bool { context.role == .parent }
    var hasCrossSchoolScope: Bool { context.has(.viewCrossSchoolData) }

    var rosterDescription: String {
        switch context.role {
        case .parent: "Approved child profiles and intake status. Attendance and daily care appear in each child’s timeline."
        case .teacher: "A compact school roster for profiles and classroom context. Daily updates live in each child’s chat."
        case .schoolDirector: "Search the roster, open profiles, and switch to attendance without leaving this workspace."
        case .hqDirector: "Filter the cross-school roster, then switch to attendance in the same workspace."
        case .none: "Child profiles."
        }
    }

    var profileScopeDescription: String {
        switch context.role {
        case .parent: "Private child profile and school records"
        case .teacher: "School child profile"
        case .schoolDirector: "School-wide child profile"
        case .hqDirector: "HQ-wide child profile"
        case .none: "Child profile"
        }
    }

    func canAccess(child: Child) -> Bool { context.isInSchool(child.schoolId) }
}

struct AssignmentAccessPolicy {
    let context: AppAccessContext

    var canCreate: Bool { context.has(.createAssignments) }
    var canReview: Bool { context.has(.reviewAssignments) }
    var canSelectSchool: Bool { context.has(.viewCrossSchoolData) }
    var canTargetMultipleStaffRoles: Bool { context.has(.viewCrossSchoolData) }

    func canReview(serverAllowsReview: Bool) -> Bool {
        serverAllowsReview && canReview
    }

    func canAssign(to memberRole: SchoolRole, category: AssignmentCategory) -> Bool {
        guard category == .training || category == .curriculum else { return false }
        return memberRole == .teacher || (canTargetMultipleStaffRoles && memberRole == .schoolDirector)
    }

    func canAssign(
        to memberUserId: UUID,
        role memberRole: SchoolRole,
        accessState: String?,
        category: AssignmentCategory
    ) -> Bool {
        guard memberUserId != context.userId else { return false }

        if [.parent, .teacher].contains(memberRole),
           accessState?.lowercased() == "onboarding" {
            return false
        }

        return canAssign(to: memberRole, category: category)
    }
}

struct PaperworkAccessPolicy {
    let context: AppAccessContext

    var canView: Bool { context.has(.viewPaperwork) }
    var canCreate: Bool { context.has(.createPaperwork) }
    var canReview: Bool { context.has(.reviewPaperwork) }
    var canSelectSchool: Bool { context.has(.viewCrossSchoolData) }
}

struct EventAccessPolicy {
    let context: AppAccessContext
    var canManage: Bool { context.has(.manageEvents) }
    var canSelectSchool: Bool { context.has(.viewCrossSchoolData) }

    func canInvite(memberRole: SchoolRole) -> Bool {
        guard context.role == .teacher else { return canManage }
        return memberRole == .parent
            || memberRole.has(.manageMemberOnboarding)
            || memberRole.has(.manageSchools)
    }
}

struct OnboardingAccessPolicy {
    let context: AppAccessContext
    var usesChecklist: Bool { context.has(.useAccessChecklist) }
    var canManageMembers: Bool { context.has(.manageMemberOnboarding) }
    var canManageDirectors: Bool { context.has(.manageDirectorOnboarding) }
}

struct AttendanceAccessPolicy {
    let context: AppAccessContext
    var canRecord: Bool { context.has(.recordAttendance) }
    var canCorrect: Bool { context.has(.correctAttendance) }
    var hasCrossSchoolScope: Bool { context.has(.viewCrossSchoolAttendance) }
    var canManageCodes: Bool { context.has(.manageAttendanceCodes) }
}

struct CareAccessPolicy {
    let context: AppAccessContext
    var canRecord: Bool { context.has(.recordCare) }
    var hasCrossSchoolScope: Bool { context.has(.viewCrossSchoolData) }
}

struct FamilyRequestAccessPolicy {
    let context: AppAccessContext
    var canCreate: Bool { context.has(.createFamilyRequest) }
    var canHandle: Bool { context.has(.handleFamilyRequests) }

    var emptyDescription: String {
        canCreate
            ? "Send an absence, pickup change, medication question, or general request to school staff."
            : "New parent requests for this school will appear here."
    }
}

struct PaymentAccessPolicy {
    let context: AppAccessContext
    var canView: Bool { context.has(.viewBilling) }
    var canManage: Bool { context.accessState == "full" && (context.has(.manageSchoolBilling) || context.role == .hqDirector) }
    var canManageRecipientInstructions: Bool {
        canManage
    }
    var hasCrossSchoolScope: Bool { context.has(.viewCrossSchoolBilling) }
    var usesSchoolSetupPresentation: Bool { canManage }

    /// The server verifies the payer's active membership. The client keeps the
    /// same named-payer guard so a teacher or director can complete an
    /// onboarding fee without gaining the parent billing workspace.
    func canPay(invoice: ZelleInvoice) -> Bool {
        context.userId == invoice.payerUserId
            && context.isInSchool(invoice.schoolId)
    }

    /// School directors review their school's parent/teacher payments. HQ directors
    /// oversee payments across all schools in the organization, including director onboarding.
    func canReview(invoice: ZelleInvoice) -> Bool {
        guard context.accessState == "full", context.userId != invoice.payerUserId else { return false }
        if invoice.payerRole == .schoolDirector {
            return context.role == .hqDirector && invoice.isOnboardingInvoice
        }
        if context.role == .hqDirector { return true }
        return canManage && context.isInSchool(invoice.schoolId)
    }
}

struct NotificationAccessPolicy {
    let context: AppAccessContext
    var canCompose: Bool { context.has(.composeSchoolNotifications) }

    var inboxDescription: String {
        switch context.role {
        case .parent:
            "Child connections, assignments, attendance, urgent care, chat invitations, and school announcements. Parent needs are sent as Family Requests."
        case .teacher:
            "Training, family requests, medication alerts, director announcements, events, and child workflow reminders."
        case .schoolDirector, .hqDirector:
            "Assignments, child connection reviews, attendance exceptions, medication alerts, chat changes, and school announcements."
        case .none:
            "School notifications."
        }
    }
}
