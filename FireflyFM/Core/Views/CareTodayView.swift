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
                Section(child.fullName) {
                    Picker("Care type", selection: $eventType) {
                        ForEach(ChildCareEventType.composerCases) { type in Label(type.title, systemImage: type.symbol).tag(type) }
                    }
                    DatePicker("Time", selection: $occurredAt)
                    Toggle("Staff Only", isOn: $staffOnly)
                    Text("Routine entries are visible to linked parents by default. Use Staff Only only when the event should remain internal.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section(eventType.title) {
                    TextField(summaryPlaceholder, text: $summary, axis: .vertical).lineLimit(2...5)
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
            .navigationTitle("Log Daily Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || isPreparingMedia
                                  || (eventType == .medication && selectedMedicationTaskId == nil))
                }
            }
            .task { await loadMedicationTasks() }
            .onChange(of: selectedMediaItem) { _, item in Task { await prepareMedia(item) } }
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
        var details: [String: FireflyJSONValue] = ["summary": .string(summary.trimmingCharacters(in: .whitespacesAndNewlines))]
        if !amount.isEmpty { details[eventType == .medication ? "dosage_given" : "amount"] = .string(amount) }
        if !outcome.isEmpty { details["outcome"] = .string(outcome) }
        Task {
            var uploadedMedia: ChatAttachmentUploadResult?
            do {
                if !staffOnly, let roomId, let mediaData, let mediaContentType, let mediaFileName {
                    uploadedMedia = try await ChatService.shared.uploadMediaAttachment(
                        data: mediaData,
                        fileName: mediaFileName,
                        contentType: mediaContentType,
                        schoolId: child.schoolId,
                        roomId: roomId
                    )
                }
                _ = try await SchoolOperationsService.shared.recordCareEvent(
                    childId: child.id, type: eventType, occurredAt: occurredAt,
                    details: details, isStaffOnly: staffOnly, medicationTaskId: selectedMedicationTaskId,
                    idempotencyKey: idempotencyKey
                )
                if let roomId, let uploadedMedia {
                    try await ChatService.shared.sendMessage(
                        roomId: roomId,
                        text: nil,
                        mediaPath: uploadedMedia.path,
                        attachmentType: uploadedMedia.type,
                        attachmentName: uploadedMedia.name,
                        attachmentSize: uploadedMedia.size
                    )
                }
                await MainActor.run { isSaving = false; onSaved(); dismiss() }
            } catch {
                if let uploadedMedia { try? await SchoolService.shared.removePrivateFiles(paths: [uploadedMedia.path]) }
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
