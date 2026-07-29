import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatDailyActivityComposerView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    let childId: UUID
    let roomId: UUID

    @State private var child: Child?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let child {
                CareEventComposerView(child: child, roomId: roomId) {}
            } else if let errorMessage {
                ContentUnavailableView(
                    "Daily activity unavailable",
                    systemImage: "heart.text.square",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Opening daily activity")
                    .tint(AppConstants.Colors.primaryAction)
            }
        }
        .task { await loadChild() }
    }

    @MainActor
    private func loadChild() async {
        guard child == nil, let schoolId = appSession.activeSchool?.id else { return }
        do {
            child = try await SchoolWorkflowService.shared.fetchChildren(schoolId: schoolId)
                .first(where: { $0.id == childId })
            if child == nil { errorMessage = "You may no longer have access to this child." }
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not open the child", error)
        }
    }
}

struct CareTodayView: View {
    var initialChildId: UUID? = nil
    var opensComposer: Bool = false
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var children: [Child] = []
    @State private var events: [ChildCareEvent] = []
    @State private var searchText = ""
    @State private var typeFilter: ChildCareEventType?
    @State private var composingChild: Child?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var didOpenInitialComposer = false

    private var childrenById: [UUID: Child] { Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0) }) }
    private var filteredEvents: [ChildCareEvent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return events.filter { event in
            (typeFilter == nil || event.eventType == typeFilter)
                && (query.isEmpty || childrenById[event.childId]?.fullName.localizedCaseInsensitiveContains(query) == true)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppConstants.Colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                filters
                if isLoading {
                    Spacer(); ProgressView().tint(AppConstants.Colors.accessibleYellow); Spacer()
                } else if filteredEvents.isEmpty {
                    Spacer()
                    ContentUnavailableView("No care events today", systemImage: "heart.text.square", description: Text("Meals, bottles, naps, potty, diapers, medication, health checks, activities, notes, and photos appear here."))
                    Spacer()
                } else {
                    List(filteredEvents) { event in CareEventRow(event: event, child: childrenById[event.childId]) }
                        .listStyle(.plain).scrollContentBackground(.hidden).refreshable { await load() }
                }
                if let errorMessage { Text(errorMessage).font(.caption).foregroundColor(.red).padding(.horizontal) }
            }

            if children.isEmpty == false && appSession.role != .hqDirector {
                Menu {
                    ForEach(children) { child in Button(child.fullName) { composingChild = child } }
                } label: {
                    Image(systemName: "plus").font(.title2.bold()).foregroundColor(AppConstants.Colors.brandNavy)
                        .frame(width: 58, height: 58).background(AppConstants.Colors.accessibleYellow).clipShape(Circle()).shadow(radius: 5)
                }
                .padding()
            }
        }
        .navigationTitle("Care Today")
        .sheet(item: $composingChild) { child in
            CareEventComposerView(child: child) { Task { await load() } }
        }
        .task(id: appSession.activeMembershipId) { await load() }
    }

    private var filters: some View {
        VStack(spacing: 10) {
            FireflySearchField(placeholder: "Search children", text: $searchText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    filterButton("All", type: nil)
                    ForEach(ChildCareEventType.allCases) { type in filterButton(type.title, type: type) }
                }
            }
        }.padding(.horizontal)
    }

    private func filterButton(_ title: String, type: ChildCareEventType?) -> some View {
        Button(title) { typeFilter = type }.font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7)
            .background(typeFilter == type ? AppConstants.Colors.accessibleYellow : AppConstants.Colors.card)
            .foregroundColor(typeFilter == type ? AppConstants.Colors.brandNavy : AppConstants.Colors.primaryText).clipShape(Capsule())
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do {
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? Date()
            if appSession.role == .hqDirector {
                children = try await SchoolWorkflowService.shared.fetchAllChildrenForHQ()
                events = []
                for schoolId in Set(children.map(\.schoolId)) {
                    events += try await SchoolOperationsService.shared.fetchCareEvents(schoolId: schoolId, start: start, end: end)
                }
                events.sort { $0.occurredAt > $1.occurredAt }
            } else if let schoolId = appSession.activeSchool?.id {
                async let loadedChildren = SchoolWorkflowService.shared.fetchChildren(schoolId: schoolId)
                async let loadedEvents = SchoolOperationsService.shared.fetchCareEvents(schoolId: schoolId, start: start, end: end)
                children = try await loadedChildren; events = try await loadedEvents
            }
            if opensComposer, !didOpenInitialComposer,
               let initialChildId,
               let child = children.first(where: { $0.id == initialChildId }) {
                didOpenInitialComposer = true
                composingChild = child
            }
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) { isLoading = false }
        catch { isLoading = false; errorMessage = AppErrorMessage.school("Could not load today’s care", error) }
    }
}

private struct CareEventRow: View {
    let event: ChildCareEvent
    let child: Child?
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: event.eventType.symbol).font(.headline).foregroundColor(AppConstants.Colors.accessibleYellow)
                .frame(width: 38, height: 38).background(AppConstants.Colors.background).clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(child?.fullName ?? "Child").font(.headline)
                    Spacer(); Text(event.occurredAt.formatted(date: .omitted, time: .shortened)).font(.caption)
                }
                Text(event.eventType.title).font(.subheadline.bold()).foregroundColor(AppConstants.Colors.accessibleYellow)
                ForEach(event.details.keys.sorted(), id: \.self) { key in
                    if key != "photo_path", let value = event.details[key]?.stringValue, value.isEmpty == false {
                        Text("\(key.replacingOccurrences(of: "_", with: " ").capitalized): \(value)")
                            .font(.caption).foregroundColor(AppConstants.Colors.secondaryText)
                    }
                }
                if !event.developmentalDomains.isEmpty {
                    Text(event.developmentalDomains.compactMap { ChildDevelopmentalDomain(rawValue: $0)?.title }.joined(separator: " • "))
                        .font(.caption2).foregroundColor(AppConstants.Colors.primaryAction)
                }
                if event.reportHighlight {
                    Label("Progress Highlight", systemImage: "star.circle.fill")
                        .font(.caption2.bold()).foregroundColor(AppConstants.Colors.primaryAction)
                }
                if let photoPath = event.photoPath { CareEventPhoto(path: photoPath) }
                if event.visibility == "staff_only" { Label("Staff Only", systemImage: "lock.fill").font(.caption2).foregroundColor(.orange) }
            }
        }
        .padding(.vertical, 6).listRowBackground(AppConstants.Colors.card)
    }
}

private struct CareEventComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let child: Child
    var roomId: UUID? = nil
    var onSaved: () -> Void

    @State private var eventType: ChildCareEventType = .meal
    @State private var occurredAt = Date()
    @State private var summary = ""
    @State private var amount = ""
    @State private var outcome = ""
    @State private var staffOnly = false
    @State private var selectedDomains: Set<ChildDevelopmentalDomain> = []
    @State private var reportHighlight = false
    @State private var showsMoreOptions = false
    @State private var medicationTasks: [MedicationTask] = []
    @State private var selectedMedicationTaskId: UUID?
    @State private var selectedMediaItem: PhotosPickerItem?
    @State private var mediaData: Data?
    @State private var mediaContentType: String?
    @State private var mediaFileName: String?
    @State private var isPreparingMedia = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let idempotencyKey = UUID().uuidString

    var body: some View {
        NavigationStack {
            Form {
                Section("What happened with \(child.firstName)?") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(ChildCareEventType.composerCases) { type in
                            Button {
                                eventType = type
                            } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: type.symbol).font(.headline)
                                    Text(type.title).font(.caption.bold()).lineLimit(2)
                                }
                                .foregroundColor(eventType == type ? AppConstants.Colors.brandNavy : AppConstants.Colors.primaryText)
                                .frame(maxWidth: .infinity, minHeight: 66)
                                .background(eventType == type ? AppConstants.Colors.fireflyGlow : AppConstants.Colors.background)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(eventType == type ? AppConstants.Colors.primaryAction : AppConstants.Colors.separator, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(type.title)
                            .accessibilityAddTraits(eventType == type ? .isSelected : [])
                        }
                    }
                }
                Section(eventType.title) {
                    quickPresets
                    TextField(summaryPlaceholder + (eventType.requiresNarrative ? "" : " (optional)"), text: $summary, axis: .vertical)
                        .lineLimit(2...5)
                    if [.meal, .bottle, .medication, .healthCheck].contains(eventType) {
                        TextField(amountPlaceholder, text: $amount)
                    }
                    if [.potty, .diaper, .nap, .healthCheck, .activity, .observation, .incident].contains(eventType) {
                        TextField(outcomePlaceholder, text: $outcome)
                    }
                    if eventType == .medication {
                        if medicationTasks.isEmpty {
                            Text("No approved medication task is due. Medication cannot be recorded without an approved authorization.")
                                .font(.caption).foregroundColor(.red)
                        } else {
                            Picker("Authorized task", selection: $selectedMedicationTaskId) {
                                Text("Select a due task").tag(Optional<UUID>.none)
                                ForEach(medicationTasks) { task in
                                    Text(task.dueAt.formatted(date: .abbreviated, time: .shortened)).tag(Optional(task.id))
                                }
                            }
                        }
                    }
                }
                if eventType.isDevelopmental {
                    Section("Progress") {
                        Text("Choose any areas this moment demonstrates. These labels make year-end evidence easier to review.")
                            .font(.caption).foregroundColor(.secondary)
                        ForEach(ChildDevelopmentalDomain.allCases) { domain in
                            Button {
                                if selectedDomains.contains(domain) { selectedDomains.remove(domain) }
                                else { selectedDomains.insert(domain) }
                            } label: {
                                HStack {
                                    Label(domain.title, systemImage: domain.symbol)
                                    Spacer()
                                    if selectedDomains.contains(domain) {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(AppConstants.Colors.primaryAction)
                                    }
                                }
                            }
                            .foregroundColor(AppConstants.Colors.primaryText)
                        }
                        Toggle("Mark as a progress highlight", isOn: $reportHighlight)
                    }
                }
                Section {
                    DisclosureGroup("More options", isExpanded: $showsMoreOptions) {
                        DatePicker("Activity time", selection: $occurredAt)
                        Toggle("Staff Only", isOn: $staffOnly)
                        Text("Family sharing is the default. Staff-only entries stay out of the family chat and report evidence.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                if roomId != nil, !staffOnly {
                    Section("Add to this update") {
                        PhotosPicker(selection: $selectedMediaItem, matching: .any(of: [.images, .videos])) {
                            Label(mediaData == nil ? "Add Photo or Video" : "Replace Photo or Video", systemImage: "photo.on.rectangle.angled")
                        }
                        if isPreparingMedia { ProgressView("Preparing attachment") }
                        if let mediaData, mediaContentType?.hasPrefix("image/") == true, let image = UIImage(data: mediaData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if mediaData != nil, mediaContentType?.hasPrefix("video/") == true {
                            Label(mediaFileName ?? "Video ready", systemImage: "play.rectangle.fill")
                                .foregroundColor(AppConstants.Colors.primaryAction)
                        }
                        Text("The activity and its media are shared together in the child’s family chat. Voice messages can be added from the microphone beside +.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if roomId != nil, staffOnly {
                    Section {
                        Label("Staff-only activities are not posted to the family chat.", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
            }
            .navigationTitle("Daily Update")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : (staffOnly ? "Save Note" : "Share")) { save() }
                        .disabled(isSaving || (eventType.requiresNarrative && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                  || isPreparingMedia
                                  || (eventType == .medication && selectedMedicationTaskId == nil))
                }
            }
            .task { await loadMedicationTasks() }
            .onChange(of: selectedMediaItem) { _, item in Task { await prepareMedia(item) } }
            .onChange(of: eventType) { _, type in
                amount = ""
                outcome = ""
                selectedDomains.removeAll()
                reportHighlight = type.isDevelopmental
            }
        }
    }

    @ViewBuilder
    private var quickPresets: some View {
        let configuration = quickPresetConfiguration
        let values = configuration.values
        let usesAmount = configuration.usesAmount
        if !values.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        let isSelected = usesAmount ? amount == value : outcome == value
                        Button(value) {
                            if usesAmount { amount = value } else { outcome = value }
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isSelected ? AppConstants.Colors.fireflyGlow : AppConstants.Colors.background)
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var quickPresetConfiguration: (values: [String], usesAmount: Bool) {
        switch eventType {
        case .meal: (["All", "Most", "Some", "None"], true)
        case .bottle: (["2 oz", "4 oz", "6 oz", "All"], true)
        case .nap: (["30 min", "1 hr", "1.5 hr", "2+ hr"], false)
        case .potty: (["Successful", "Tried", "Accident"], false)
        case .diaper: (["Dry", "Wet", "Bowel movement"], false)
        default: ([], false)
        }
    }

    private var summaryPlaceholder: String {
        switch eventType { case .meal: "Food and notes"; case .bottle: "Bottle details"; case .nap: "Nap notes"; case .potty: "Potty notes"; case .diaper: "Diaper notes"; case .medication: "Administration notes"; case .healthCheck: "Health observation"; case .activity: "Learning activity"; case .observation: "What did you observe?"; case .kudos: "What went well?"; case .incident: "What happened?"; case .note: "Note"; case .photo: "Photo caption" }
    }
    private var amountPlaceholder: String { eventType == .healthCheck ? "Temperature or measurement" : eventType == .medication ? "Dosage given" : "Amount" }
    private var outcomePlaceholder: String { eventType == .nap ? "Duration" : eventType == .healthCheck ? "Action taken" : "Outcome" }

    @MainActor private func loadMedicationTasks() async {
        do {
            medicationTasks = try await SchoolWorkflowService.shared.fetchMedicationTasks(schoolId: child.schoolId, childId: child.id)
            selectedMedicationTaskId = medicationTasks.first?.id
        } catch where AppErrorMessage.isCancellation(error) { return }
        catch { errorMessage = AppErrorMessage.school("Could not load medication tasks", error) }
    }

    @MainActor private func prepareMedia(_ item: PhotosPickerItem?) async {
        guard let item else {
            mediaData = nil
            mediaContentType = nil
            mediaFileName = nil
            return
        }
        isPreparingMedia = true; errorMessage = nil
        defer { isPreparingMedia = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw SchoolWorkflowError.notFound
            }
            let type = item.supportedContentTypes.first ?? .jpeg
            let ext = type.preferredFilenameExtension ?? (type.conforms(to: .movie) ? "mov" : "jpg")
            let name = type.conforms(to: .movie) ? "Daily update video.\(ext)" : "Daily update photo.\(ext)"
            try UploadPolicy.validate(data: data, fileName: name)
            mediaData = data
            mediaContentType = type.preferredMIMEType ?? (type.conforms(to: .movie) ? "video/quicktime" : "image/jpeg")
            mediaFileName = name
        } catch {
            mediaData = nil
            mediaContentType = nil
            mediaFileName = nil
            errorMessage = AppErrorMessage.school("Could not prepare the attachment", error)
        }
    }

    private func save() {
        isSaving = true
        var details: [String: FireflyJSONValue] = [:]
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty { details["summary"] = .string(trimmedSummary) }
        if !amount.isEmpty { details[eventType == .medication ? "dosage_given" : "amount"] = .string(amount) }
        if !outcome.isEmpty { details["outcome"] = .string(outcome) }
        Task {
            var uploadedMedia: ChatAttachmentUploadResult?
            var sentMediaMessage: ChatMessageModel?
            do {
                if !staffOnly, let roomId, let mediaData, let mediaContentType, let mediaFileName {
                    uploadedMedia = try await ChatService.shared.uploadMediaAttachment(
                        data: mediaData,
                        fileName: mediaFileName,
                        contentType: mediaContentType,
                        schoolId: child.schoolId,
                        roomId: roomId
                    )
                    sentMediaMessage = try await ChatService.shared.sendMessage(
                        roomId: roomId,
                        text: nil,
                        mediaPath: uploadedMedia?.path,
                        attachmentType: uploadedMedia?.type,
                        attachmentName: uploadedMedia?.name,
                        attachmentSize: uploadedMedia?.size
                    )
                }
                _ = try await SchoolOperationsService.shared.recordCareEvent(
                    childId: child.id, type: eventType, occurredAt: occurredAt,
                    details: details, isStaffOnly: staffOnly, medicationTaskId: selectedMedicationTaskId,
                    sourceMessageId: sentMediaMessage?.id,
                    developmentalDomains: Array(selectedDomains),
                    reportHighlight: !staffOnly && reportHighlight,
                    idempotencyKey: idempotencyKey
                )
                await MainActor.run { isSaving = false; onSaved(); dismiss() }
            } catch {
                if let sentMediaMessage {
                    try? await ChatService.shared.deleteMessage(id: sentMediaMessage.id)
                } else if let uploadedMedia {
                    try? await SchoolService.shared.removePrivateFiles(paths: [uploadedMedia.path])
                }
                await MainActor.run { isSaving = false; errorMessage = AppErrorMessage.school("Could not record care", error) }
            }
        }
    }
}

private struct CareEventPhoto: View {
    let path: String
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else if phase.error != nil { Image(systemName: "photo.badge.exclamationmark").foregroundColor(.secondary) }
                    else { ProgressView() }
                }
            } else { ProgressView() }
        }
        .frame(maxWidth: .infinity).frame(height: 180).background(AppConstants.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task { url = try? await SchoolService.shared.signedPrivateFileURL(path: path) }
    }
}

struct ChatActivityLabelView: View {
    @Environment(\.dismiss) private var dismiss

    let message: ChatMessageModel
    var onSaved: (ChildCareEvent) -> Void

    @State private var eventType: ChildCareEventType = .activity
    @State private var summary = ""
    @State private var selectedDomains: Set<ChildDevelopmentalDomain> = []
    @State private var reportHighlight = true
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let idempotencyKey = UUID().uuidString

    private var isEditing: Bool { message.linkedCareEventId != nil }
    private var isAudio: Bool {
        message.audioPath != nil || message.audioUrl != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isEditing ? "Daily log label" : "What does this media show?") {
                    ForEach(ChildCareEventType.mediaLabelCases) { type in
                        Button {
                            eventType = type
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.symbol)
                                    .frame(width: 28)
                                    .foregroundColor(AppConstants.Colors.primaryAction)
                                Text(mediaLabelTitle(type))
                                Spacer()
                                if eventType == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppConstants.Colors.primaryAction)
                                }
                            }
                        }
                        .foregroundColor(AppConstants.Colors.primaryText)
                    }
                }

                Section("Optional note") {
                    TextField("What is important about this moment?", text: $summary, axis: .vertical)
                        .lineLimit(2...5)
                    Text("The original media and timestamp stay unchanged.")
                        .font(.caption).foregroundColor(.secondary)
                }

                if eventType.isDevelopmental {
                    Section("Development areas") {
                        ForEach(ChildDevelopmentalDomain.allCases) { domain in
                            Button {
                                if selectedDomains.contains(domain) { selectedDomains.remove(domain) }
                                else { selectedDomains.insert(domain) }
                            } label: {
                                HStack {
                                    Label(domain.title, systemImage: domain.symbol)
                                    Spacer()
                                    if selectedDomains.contains(domain) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppConstants.Colors.primaryAction)
                                    }
                                }
                            }
                            .foregroundColor(AppConstants.Colors.primaryText)
                        }
                    }
                }

                Section {
                    Toggle("Mark as a progress highlight", isOn: $reportHighlight)
                    if isAudio {
                        Text("Only this label and note are eligible for future report review. The voice recording itself is not transcribed or sent to AI.")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("A director will still review evidence before it can be used in a progress report.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle(isEditing ? "Edit Daily Log" : "Add to Daily Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving || isLoading)
                }
            }
            .task { await loadExistingEvent() }
        }
    }

    private func mediaLabelTitle(_ type: ChildCareEventType) -> String {
        switch type {
        case .activity: "Learning Activity"
        case .observation: "Observation"
        case .kudos: "Milestone or Kudos"
        case .note: "Daily Moment"
        default: type.title
        }
    }

    @MainActor
    private func loadExistingEvent() async {
        guard let eventId = message.linkedCareEventId else { return }
        isLoading = true
        do {
            let event = try await SchoolOperationsService.shared.fetchCareEvent(id: eventId)
            eventType = event.eventType
            summary = event.details["summary"]?.stringValue ?? ""
            selectedDomains = Set(event.developmentalDomains.compactMap(ChildDevelopmentalDomain.init(rawValue:)))
            reportHighlight = event.reportHighlight
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = AppErrorMessage.school("Could not load the daily log label", error)
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let saved: ChildCareEvent
                if let eventId = message.linkedCareEventId {
                    saved = try await SchoolOperationsService.shared.correctLinkedChildActivity(
                        eventId: eventId,
                        type: eventType,
                        summary: trimmedSummary.isEmpty ? nil : trimmedSummary,
                        developmentalDomains: Array(selectedDomains),
                        reportHighlight: reportHighlight
                    )
                } else {
                    saved = try await SchoolOperationsService.shared.labelChatMessageAsActivity(
                        messageId: message.id,
                        type: eventType,
                        summary: trimmedSummary.isEmpty ? nil : trimmedSummary,
                        developmentalDomains: Array(selectedDomains),
                        reportHighlight: reportHighlight,
                        idempotencyKey: idempotencyKey
                    )
                }
                await MainActor.run {
                    isSaving = false
                    onSaved(saved)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not save the daily log label", error)
                }
            }
        }
    }
}
