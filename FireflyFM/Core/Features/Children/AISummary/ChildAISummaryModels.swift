import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum ChildAISummaryAvailability: Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceDisabled
    case modelNotReady
    case unavailable

    var message: String {
        switch self {
        case .available:
            "Apple’s on-device model is ready."
        case .deviceNotEligible:
            "This device does not support Apple’s on-device Foundation Model."
        case .appleIntelligenceDisabled:
            "Turn on Apple Intelligence in Settings to use on-device summaries."
        case .modelNotReady:
            "Apple’s on-device model is still downloading or preparing. Try again later."
        case .unavailable:
            "The on-device model is not available on this system."
        }
    }
}

struct ChildAISummarySnapshot: Equatable {
    let startDate: Date
    let endDate: Date
    let messageCount: Int
    let attendanceCount: Int
    let careEventCount: Int
    let goalCount: Int
    let attachmentCount: Int
    let omittedMessageCount: Int

    var sourceDescription: String {
        var parts = [
            "\(messageCount) messages/cards",
            "\(attendanceCount) attendance records",
            "\(careEventCount) care activities",
            "\(goalCount) goals",
            "\(attachmentCount) attachments (metadata only)"
        ]
        if omittedMessageCount > 0 {
            parts.append("\(omittedMessageCount) older messages omitted for model capacity")
        }
        return parts.joined(separator: " · ")
    }
}

struct ChildAISummarySourceBundle {
    let child: Child
    let startDate: Date
    let endDate: Date
    let messages: [ChatMessageModel]
    let attendance: [AttendanceSession]
    let careEvents: [ChildCareEvent]
    let goals: [ChildGoal]
    let directory: [SchoolDirectoryEntry]
}

struct ChildAISummaryPrompt {
    let text: String
    let snapshot: ChildAISummarySnapshot

    static func build(from source: ChildAISummarySourceBundle, maximumCharacters: Int = 12_000) -> ChildAISummaryPrompt {
        let directory = Dictionary(uniqueKeysWithValues: source.directory.map { ($0.userId, $0) })
        let eligibleMessages = source.messages
            .filter { !$0.isDeleted && $0.createdAt >= source.startDate && $0.createdAt <= source.endDate }
            .filter { $0.linkedCareEventId == nil }
            .sorted { $0.createdAt > $1.createdAt }

        let attendance = source.attendance
            .filter { $0.childId == source.child.id && $0.attendanceDate >= source.startDate && $0.attendanceDate <= source.endDate }
            .sorted { $0.attendanceDate > $1.attendanceDate }
        let careEvents = source.careEvents
            .filter { $0.childId == source.child.id && $0.occurredAt >= source.startDate && $0.occurredAt <= source.endDate }
            .sorted { $0.occurredAt > $1.occurredAt }
        let goals = source.goals.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var attachmentCount = 0
        var fixedSections: [String] = []
        fixedSections.append("CHILD: \(source.child.fullName)")
        fixedSections.append("PERIOD: \(formatter.string(from: source.startDate)) through \(formatter.string(from: source.endDate))")

        let attendanceLines = attendance.map { record in
            let note = cleaned(record.notes).map { "; note: \($0)" } ?? ""
            return "- \(formatter.string(from: record.attendanceDate)): \(record.state.title)\(note)"
        }
        fixedSections.append("ATTENDANCE (\(attendance.count)):\n\(attendanceLines.isEmpty ? "- No records" : attendanceLines.joined(separator: "\n"))")

        let careLines = careEvents.map { event in
            let recorder = directory[event.recordedBy].map { "\($0.displayName) (\($0.schoolRole.title))" } ?? "Authorized staff"
            let details = event.details.keys.sorted().compactMap { key -> String? in
                guard key != "photo_path", let value = event.details[key] else { return nil }
                return "\(key.replacingOccurrences(of: "_", with: " "))=\(display(value))"
            }.joined(separator: ", ")
            return "- \(formatter.string(from: event.occurredAt)) · \(event.eventType.title) · by \(recorder)\(details.isEmpty ? "" : " · \(details)")"
        }
        fixedSections.append("ACTIVITY AND CARE CARDS (\(careEvents.count)):\n\(careLines.isEmpty ? "- No records" : careLines.joined(separator: "\n"))")

        let goalLines = goals.map { goal in
            let notes = cleaned(goal.notes).map { " · notes: \($0)" } ?? ""
            return "- \(goal.title) · status: \(goal.status)\(notes)"
        }
        fixedSections.append("GOALS (\(goals.count)):\n\(goalLines.isEmpty ? "- No goals" : goalLines.joined(separator: "\n"))")

        let header = """
        Create a concise factual review draft using only the supplied source material.
        Use these headings: Overview, Communication themes, Attendance and care, Goals and progress, Items needing human follow-up.
        Attribute important statements to the source type and date when useful. Distinguish direct facts from possible patterns. If evidence is sparse or conflicting, say so. Do not diagnose, infer protected traits, invent facts, or make medical, disciplinary, legal, safety, or eligibility recommendations. Never treat an attachment name as evidence of its contents.

        """
        let fixed = fixedSections.joined(separator: "\n\n")
        let messageBudget = max(1_500, maximumCharacters - header.count - fixed.count - 80)
        var messageLines: [String] = []
        var usedCharacters = 0
        var includedMessageCount = 0

        for message in eligibleMessages {
            let sender = directory[message.senderId].map { "\($0.displayName) (\($0.schoolRole.title))" } ?? "Authorized participant"
            let body = cleaned(message.text) ?? "No text"
            var metadata: [String] = []
            if message.entryKind != "message" { metadata.append("card type: \(message.entryKind)") }
            if let attachment = attachmentDescription(message) {
                metadata.append(attachment)
                attachmentCount += 1
            }
            let suffix = metadata.isEmpty ? "" : " [\(metadata.joined(separator: "; "))]"
            let line = "- \(formatter.string(from: message.createdAt)) · \(sender): \(body)\(suffix)"
            guard usedCharacters + line.count <= messageBudget else { break }
            messageLines.append(line)
            usedCharacters += line.count + 1
            includedMessageCount += 1
        }

        let messageSection = "MESSAGES AND CARDS (newest first; \(includedMessageCount) included):\n\(messageLines.isEmpty ? "- No eligible messages" : messageLines.joined(separator: "\n"))"
        let prompt = header + fixed + "\n\n" + messageSection
        let snapshot = ChildAISummarySnapshot(
            startDate: source.startDate,
            endDate: source.endDate,
            messageCount: includedMessageCount,
            attendanceCount: attendance.count,
            careEventCount: careEvents.count,
            goalCount: goals.count,
            attachmentCount: attachmentCount,
            omittedMessageCount: max(0, eligibleMessages.count - includedMessageCount)
        )
        return ChildAISummaryPrompt(text: prompt, snapshot: snapshot)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func attachmentDescription(_ message: ChatMessageModel) -> String? {
        guard message.attachmentType != nil
                || message.attachmentName != nil
                || message.mediaPath != nil
                || message.audioPath != nil
                || message.filePath != nil
        else { return nil }

        var parts = ["attachment metadata only"]
        if let type = cleaned(message.attachmentType) { parts.append("type \(type)") }
        if let name = cleaned(message.attachmentName) { parts.append("name \(name)") }
        if let size = message.attachmentSize { parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
        if let duration = message.audioDurationSeconds { parts.append("audio duration \(Int(duration.rounded())) seconds") }
        return parts.joined(separator: ", ")
    }

    private static func display(_ value: FireflyJSONValue) -> String {
        switch value {
        case .string(let value): return value
        case .number(let value): return value.formatted()
        case .bool(let value): return value ? "yes" : "no"
        case .object(let value):
            return value.keys.sorted().compactMap { key in value[key].map { "\(key): \(display($0))" } }.joined(separator: ", ")
        case .array(let value): return value.map { display($0) }.joined(separator: ", ")
        case .null: return "not set"
        }
    }
}

struct ChildAISummaryClient {
    var fetchRooms: (UUID) async throws -> [ChatRoomListItem]
    var fetchMessages: (UUID) async throws -> [ChatMessageModel]
    var fetchAttendance: (UUID, Date, Date) async throws -> [AttendanceSession]
    var fetchCareEvents: (UUID, UUID, Date, Date) async throws -> [ChildCareEvent]
    var fetchGoals: (UUID) async throws -> [ChildGoal]
    var fetchDirectory: (UUID) async throws -> [SchoolDirectoryEntry]

    static let live = ChildAISummaryClient(
        fetchRooms: { try await ChatService.shared.fetchMyRoomListItems(schoolId: $0, includeAllSchoolRooms: true) },
        fetchMessages: { try await ChatService.shared.fetchMessages(for: $0, limit: 150) },
        fetchAttendance: { try await SchoolOperationsService.shared.fetchAttendance(schoolId: $0, startDate: $1, endDate: $2) },
        fetchCareEvents: { try await SchoolOperationsService.shared.fetchCareEvents(schoolId: $0, start: $2, end: $3, childId: $1) },
        fetchGoals: { try await SchoolWorkflowService.shared.fetchChildGoals(childId: $0) },
        fetchDirectory: { try await SchoolOperationsService.shared.fetchDirectory(schoolId: $0) }
    )
}

@MainActor
@Observable
final class ChildAISummaryModel {
    private let client: ChildAISummaryClient
    private(set) var summary: String?
    private(set) var snapshot: ChildAISummarySnapshot?
    private(set) var generatedAt: Date?
    private(set) var isGenerating = false
    private(set) var errorMessage: String?

    init() {
        client = .live
    }

    init(client: ChildAISummaryClient) {
        self.client = client
    }

    var availability: ChildAISummaryAvailability {
        OnDeviceChildSummaryGenerator.availability
    }

    func generate(for child: Child, days: Int = 90) async {
        guard availability == .available else {
            errorMessage = availability.message
            return
        }

        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? .distantPast

        do {
            async let roomItems = client.fetchRooms(child.schoolId)
            async let attendance = client.fetchAttendance(child.schoolId, startDate, endDate)
            async let careEvents = client.fetchCareEvents(child.schoolId, child.id, startDate, endDate.addingTimeInterval(1))
            async let goals = client.fetchGoals(child.id)
            async let directory = client.fetchDirectory(child.schoolId)

            let rooms = try await roomItems
            let room = rooms.map(\.room).first { $0.isChildFamilyRoom && $0.subjectChildId == child.id }
            let messages: [ChatMessageModel]
            if let room {
                messages = try await client.fetchMessages(room.id)
            } else {
                messages = []
            }
            let source = ChildAISummarySourceBundle(
                child: child,
                startDate: startDate,
                endDate: endDate,
                messages: messages,
                attendance: try await attendance,
                careEvents: try await careEvents,
                goals: try await goals,
                directory: try await directory
            )
            let prompt = ChildAISummaryPrompt.build(from: source)
            summary = try await OnDeviceChildSummaryGenerator.generate(prompt: prompt.text)
            snapshot = prompt.snapshot
            generatedAt = Date()
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = "Could not create the on-device summary. \(error.localizedDescription)"
        }
    }
}

enum OnDeviceChildSummaryGenerator {
    static var availability: ChildAISummaryAvailability {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceDisabled
        case .unavailable(.modelNotReady): return .modelNotReady
        case .unavailable: return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    static func generate(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        guard availability == .available else { throw ChildAISummaryError.modelUnavailable }
        let session = LanguageModelSession(instructions: """
        You help an authorized childcare director review existing records. Produce a neutral, compact draft. Follow the user’s evidence and safety constraints exactly. Do not add facts or professional advice.
        """)
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 700)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw ChildAISummaryError.modelUnavailable
        #endif
    }
}

enum ChildAISummaryError: LocalizedError {
    case modelUnavailable

    var errorDescription: String? {
        "Apple’s on-device model is not available."
    }
}
