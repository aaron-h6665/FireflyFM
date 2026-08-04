import Foundation
import NaturalLanguage
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

enum ChildAISummaryEngine: String, CaseIterable, Identifiable {
    case localExtractive
    case appleFoundationModel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localExtractive: "Local Summary"
        case .appleFoundationModel: "Apple Intelligence"
        }
    }

    var symbol: String {
        switch self {
        case .localExtractive: "text.quote"
        case .appleFoundationModel: "apple.intelligence"
        }
    }

    var reviewLabel: String {
        switch self {
        case .localExtractive: "Locally assembled. Not saved. Verify against the source records."
        case .appleFoundationModel: "AI-generated. Not saved. Verify every statement."
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
    private(set) var engineUsed: ChildAISummaryEngine?

    init() {
        client = .live
    }

    init(client: ChildAISummaryClient) {
        self.client = client
    }

    var appleAvailability: ChildAISummaryAvailability {
        OnDeviceChildSummaryGenerator.availability
    }

    var availableEngines: [ChildAISummaryEngine] {
        appleAvailability == .available
            ? [.localExtractive, .appleFoundationModel]
            : [.localExtractive]
    }

    func generate(for child: Child, using engine: ChildAISummaryEngine = .localExtractive, days: Int = 90) async {
        guard engine != .appleFoundationModel || appleAvailability == .available else {
            errorMessage = appleAvailability.message
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
            let prompt = ChildAISummaryPrompt.build(
                from: source,
                maximumCharacters: engine == .localExtractive ? 1_000_000 : 12_000
            )
            switch engine {
            case .localExtractive:
                summary = LocalExtractiveChildSummaryGenerator.generate(from: source, snapshot: prompt.snapshot)
            case .appleFoundationModel:
                summary = try await OnDeviceChildSummaryGenerator.generate(prompt: prompt.text)
            }
            snapshot = prompt.snapshot
            engineUsed = engine
            generatedAt = Date()
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = "Could not create the on-device summary. \(error.localizedDescription)"
        }
    }
}

enum LocalExtractiveChildSummaryGenerator {
    static func generate(from source: ChildAISummarySourceBundle, snapshot: ChildAISummarySnapshot) -> String {
        let directory = Dictionary(uniqueKeysWithValues: source.directory.map { ($0.userId, $0) })
        let messages = source.messages
            .filter { !$0.isDeleted && $0.createdAt >= source.startDate && $0.createdAt <= source.endDate }
            .filter { $0.linkedCareEventId == nil }
            .sorted { $0.createdAt > $1.createdAt }
        let attendance = source.attendance
            .filter { $0.childId == source.child.id && $0.attendanceDate >= source.startDate && $0.attendanceDate <= source.endDate }
        let careEvents = source.careEvents
            .filter { $0.childId == source.child.id && $0.occurredAt >= source.startDate && $0.occurredAt <= source.endDate }
        let goals = source.goals.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let sourceText = messages.compactMap(\.text)
            + goals.flatMap { [$0.title, $0.notes].compactMap { $0 } }
            + careEvents.flatMap { event in
                [event.eventType.title] + event.details.values.compactMap { plainText($0) }
            }
        let excludedTerms = Set(
            ([source.child.firstName, source.child.lastName]
                + source.directory.flatMap { $0.displayName.split(separator: " ").map(String.init) })
                .map { $0.lowercased() }
        )
        let themes = keywords(from: sourceText.joined(separator: ". "), excluding: excludedTerms)

        var sections: [String] = []
        sections.append("""
        Overview
        - Review period: \(dateFormatter.string(from: source.startDate))–\(dateFormatter.string(from: source.endDate)).
        - Sources reviewed: \(snapshot.messageCount) messages/cards, \(snapshot.attendanceCount) attendance records, \(snapshot.careEventCount) care activities, and \(snapshot.goalCount) goals.
        """)

        var communicationLines: [String] = []
        if themes.isEmpty {
            communicationLines.append("- No recurring text themes were detected in the available records.")
        } else {
            communicationLines.append("- Frequently occurring terms: \(themes.joined(separator: ", ")).")
        }
        let excerpts = messages.compactMap { message -> String? in
            guard let text = cleaned(message.text) else { return nil }
            let sender = directory[message.senderId]
            let attribution = sender.map { "\($0.displayName) (\($0.schoolRole.title))" } ?? "Authorized participant"
            return "- \(dateFormatter.string(from: message.createdAt)) — \(attribution): \(truncated(text, limit: 220))"
        }.prefix(5)
        communicationLines.append(contentsOf: excerpts)
        if messages.isEmpty {
            communicationLines.append("- No eligible message text was available for this period.")
        }
        sections.append("Communication themes and recent excerpts\n\(communicationLines.joined(separator: "\n"))")

        let attendanceCounts = Dictionary(grouping: attendance, by: \.state)
        let attendanceSummary = AttendanceState.allCases.compactMap { state -> String? in
            guard let count = attendanceCounts[state]?.count, count > 0 else { return nil }
            return "\(state.title): \(count)"
        }
        let groupedCareEvents: [ChildCareEventType: [ChildCareEvent]] = Dictionary(
            grouping: careEvents,
            by: { $0.eventType }
        )
        var sortedCareCounts: [(title: String, count: Int)] = []
        for (eventType, events) in groupedCareEvents {
            sortedCareCounts.append((title: eventType.title, count: events.count))
        }
        sortedCareCounts.sort { lhs, rhs in
            lhs.count == rhs.count ? lhs.title < rhs.title : lhs.count > rhs.count
        }
        var careCountDescriptions: [String] = []
        for item in sortedCareCounts.prefix(8) {
            careCountDescriptions.append("\(item.title): \(item.count)")
        }
        var careLines = [
            "- Attendance: \(attendanceSummary.isEmpty ? "No records" : attendanceSummary.joined(separator: ", ")).",
            "- Care/activity cards: \(careCountDescriptions.isEmpty ? "No records" : careCountDescriptions.joined(separator: ", "))."
        ]
        if snapshot.attachmentCount > 0 {
            careLines.append("- \(snapshot.attachmentCount) attachments were present; only metadata was counted and no attachment content was analyzed.")
        }
        sections.append("Attendance and care\n\(careLines.joined(separator: "\n"))")

        let goalLines = goals.prefix(8).map { goal in
            let notes = cleaned(goal.notes).map { " — \(truncated($0, limit: 160))" } ?? ""
            return "- \(goal.title) [\(goal.status)]\(notes)"
        }
        sections.append("Goals and progress\n\(goalLines.isEmpty ? "- No goals were available." : goalLines.joined(separator: "\n"))")

        let needsAttentionCount = attendanceCounts[.needsAttention]?.count ?? 0
        let incidentCount = groupedCareEvents[.incident]?.count ?? 0
        var followUpLines: [String] = []
        if needsAttentionCount > 0 {
            followUpLines.append("- \(needsAttentionCount) attendance record(s) are marked Needs Attention.")
        }
        if incidentCount > 0 {
            followUpLines.append("- \(incidentCount) incident care card(s) appear in the review period.")
        }
        if snapshot.omittedMessageCount > 0 {
            followUpLines.append("- \(snapshot.omittedMessageCount) older message(s) were omitted from the capacity-limited source set.")
        }
        if followUpLines.isEmpty {
            followUpLines.append("- No deterministic follow-up flags were found. Review the source records before concluding that no follow-up is needed.")
        }
        sections.append("Items needing human follow-up\n\(followUpLines.joined(separator: "\n"))")

        return sections.joined(separator: "\n\n")
    }

    private static func keywords(from text: String, excluding excludedTerms: Set<String>) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        var counts: [String: Int] = [:]
        let stopWords: Set<String> = [
            "about", "after", "again", "also", "been", "before", "being", "care", "child", "could",
            "from", "have", "into", "message", "notes", "school", "summary", "that", "their", "there",
            "these", "they", "this", "today", "very", "were", "with", "would"
        ]

        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation, .omitOther]
        ) { tag, tokenRange in
            guard tag == .noun || tag == .verb || tag == .adjective else { return true }
            let token = text[tokenRange]
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            guard token.count >= 4, !stopWords.contains(token), !excludedTerms.contains(token) else { return true }
            counts[token, default: 0] += 1
            return true
        }

        return counts
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(6)
            .map(\.key)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func truncated(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func plainText(_ value: FireflyJSONValue) -> String? {
        switch value {
        case .string(let value): return value
        case .number(let value): return value.formatted()
        case .bool(let value): return value ? "yes" : "no"
        case .object(let value): return value.values.compactMap { plainText($0) }.joined(separator: " ")
        case .array(let value): return value.compactMap { plainText($0) }.joined(separator: " ")
        case .null: return nil
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
