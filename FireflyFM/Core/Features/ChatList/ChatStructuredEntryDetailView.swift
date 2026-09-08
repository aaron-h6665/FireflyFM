import SwiftUI

struct ChatStructuredEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let sourceType: String
    let sourceId: UUID
    let canHandleFamilyRequest: Bool
    let canEdit: Bool
    let mediaURL: URL?
    let mediaContentType: String?
    let mediaFileName: String?

    @State private var model = ChatStructuredEntryModel()
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var editType = "general"
    @State private var editDate = Date()
    @State private var editMessage = ""
    @State private var editDetails: [String: FireflyJSONValue] = [:]
    @State private var editDomains: Set<ChildDevelopmentalDomain> = []
    @State private var editHighlight = false
    @State private var isSavingEdit = false
    @State private var mediaSaveMessage: String?

    private let requestTypeOptions: [(id: String, title: String, subtitle: String, symbol: String)] = [
        ("absence", "Absence", "Report that your child will be away", "calendar.badge.minus"),
        ("pickup_change", "Pickup Change", "Share a change to today’s pickup", "figure.walk.circle"),
        ("medication", "Medication", "Ask about medication or authorization", "cross.case.fill"),
        ("general", "General", "Send another note to the school", "bubble.left.and.exclamationmark.bubble.right")
    ]

    private var careEvent: ChildCareEvent? { model.careEvent }
    private var familyRequest: FamilyRequest? { model.familyRequest }
    private var isLoading: Bool { model.phase.isLoading }
    private var isUpdating: Bool { model.isUpdating }
    private var errorMessage: String? { model.errorMessage }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                Group {
                    if isLoading {
                        ProgressView("Opening update")
                    } else if let careEvent {
                        careDetail(careEvent)
                    } else if let familyRequest {
                        requestDetail(familyRequest)
                    } else {
                        ContentUnavailableView(
                            "Update unavailable",
                            systemImage: "exclamationmark.bubble.fill",
                            description: Text(errorMessage ?? "This update may no longer be available.")
                        )
                    }
                }
            }
            .navigationTitle(sourceType == "child_care_events" ? "Daily Activity" : "Family Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Edit", systemImage: "pencil") { beginEditing() }
                            Button("Delete", systemImage: "trash", role: .destructive) { showingDeleteConfirmation = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                if let mediaURL {
                    ToolbarItem(placement: .primaryAction) {
                        Button { saveMedia(mediaURL) } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("Save media to Photos")
                    }
                }
            }
            .sheet(isPresented: $isEditing) { editor }
            .confirmationDialog("Delete this update?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteEntry() }
            } message: {
                Text("This removes the update from the family chat and timeline.")
            }
            .alert("Save to Photos", isPresented: Binding(get: { mediaSaveMessage != nil }, set: { if !$0 { mediaSaveMessage = nil } })) {
                Button("OK") { mediaSaveMessage = nil }
            } message: { Text(mediaSaveMessage ?? "") }
            .task { await load() }
        }
    }

    private func careDetail(_ event: ChildCareEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(title: event.eventType.title, symbol: event.eventType.symbol, date: event.occurredAt)
                detailValues(event.details, excluding: ["photo_path"])
                if !event.developmentalDomains.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Development Areas").font(.caption.bold()).foregroundColor(AppConstants.Colors.secondaryText)
                        ForEach(event.developmentalDomains, id: \.self) { rawValue in
                            if let domain = ChildDevelopmentalDomain(rawValue: rawValue) {
                                Label(domain.title, systemImage: domain.symbol)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppConstants.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if event.reportHighlight {
                    Label("Progress Highlight", systemImage: "star.circle.fill")
                        .font(.caption.bold()).foregroundColor(AppConstants.Colors.primaryAction)
                }
                if event.visibility == "staff_only" {
                    Label("Staff Only", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                }
            }
            .padding()
        }
    }

    private func requestDetail(_ request: FamilyRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(
                    title: request.requestType.replacingOccurrences(of: "_", with: " ").capitalized,
                    symbol: "person.crop.circle.badge.questionmark",
                    date: request.createdAt
                )
                Text(request.status.capitalized)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppConstants.Colors.wingMist)
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .clipShape(Capsule())
                detailValues(request.details)

                if canHandleFamilyRequest {
                    HStack {
                        Button("Acknowledge") { updateRequest(request, status: "acknowledged") }
                            .buttonStyle(.bordered)
                        Button("Complete") { updateRequest(request, status: "completed") }
                            .buttonStyle(.borderedProminent)
                    }
                    .tint(AppConstants.Colors.primaryAction)
                    .disabled(isUpdating)
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.red)
                }
            }
            .padding()
        }
    }

    private func detailHeader(title: String, symbol: String, date: Date) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundColor(AppConstants.Colors.brandNavy)
                .frame(width: 50, height: 50)
                .background(AppConstants.Colors.fireflyGlow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.bold()).foregroundColor(AppConstants.Colors.primaryText)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }
        }
    }

    private func detailValues(_ values: [String: FireflyJSONValue], excluding excluded: Set<String> = []) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(values.keys.sorted().filter { !excluded.contains($0) }, id: \.self) { key in
                if let value = values[key]?.stringValue, !value.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.secondaryText)
                        Text(value).foregroundColor(AppConstants.Colors.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppConstants.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    @MainActor
    private func load() async {
        await model.load(sourceType: sourceType, sourceId: sourceId)
    }

    private func updateRequest(_ request: FamilyRequest, status: String) {
        Task { await model.update(request, status: status) }
    }

    @ViewBuilder
    private var editor: some View {
        NavigationStack {
            Form {
                if sourceType == "child_care_events", careEvent != nil {
                    Section("What happened with this child?") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                            ForEach(ChildCareEventType.composerCases) { type in
                                Button { editType = type.rawValue } label: {
                                    VStack(spacing: 7) {
                                        Image(systemName: type.symbol).font(.headline)
                                        Text(type.title).font(.caption.bold()).lineLimit(2)
                                    }
                                    .foregroundColor(editType == type.rawValue ? AppConstants.Colors.brandNavy : AppConstants.Colors.primaryText)
                                    .frame(maxWidth: .infinity, minHeight: 66)
                                    .background(editType == type.rawValue ? AppConstants.Colors.fireflyGlow : AppConstants.Colors.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(editType == type.rawValue ? AppConstants.Colors.primaryAction : AppConstants.Colors.separator) }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(editType == type.rawValue ? .isSelected : [])
                            }
                        }
                    }
                    DatePicker("Activity time", selection: $editDate)
                    if let selectedType = ChildCareEventType(rawValue: editType) {
                        editQuickPresets(for: selectedType)
                        Section(selectedType.title) {
                            TextField(editSummaryPlaceholder(for: selectedType), text: detailBinding("summary"), axis: .vertical)
                                .lineLimit(2...5)
                            if [.meal, .bottle, .medication, .healthCheck].contains(selectedType) {
                                TextField(selectedType == .healthCheck ? "Temperature or measurement" : selectedType == .medication ? "Dosage given" : "Amount", text: detailBinding(selectedType == .medication ? "dosage_given" : "amount"))
                            }
                            if [.potty, .diaper, .nap, .healthCheck, .activity, .observation, .incident].contains(selectedType) {
                                TextField(selectedType == .nap ? "Duration" : selectedType == .healthCheck ? "Action taken" : "Outcome", text: detailBinding("outcome"))
                            }
                        }
                        if selectedType.isDevelopmental {
                            Section("Development Areas") {
                                ForEach(ChildDevelopmentalDomain.allCases) { domain in
                                    Button {
                                        if editDomains.contains(domain) { editDomains.remove(domain) } else { editDomains.insert(domain) }
                                    } label: {
                                        HStack { Label(domain.title, systemImage: domain.symbol); Spacer(); if editDomains.contains(domain) { Image(systemName: "checkmark.circle.fill").foregroundColor(AppConstants.Colors.primaryAction) } }
                                    }
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                }
                                Toggle("Mark as a progress highlight", isOn: $editHighlight)
                            }
                        }
                    }
                } else if familyRequest != nil {
                    Section("What do you need to tell the school?") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                            ForEach(requestTypeOptions, id: \.id) { option in
                                Button { editType = option.id } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Image(systemName: option.symbol).font(.headline)
                                        Text(option.title).font(.caption.bold())
                                        Text(option.subtitle).font(.caption2).multilineTextAlignment(.leading).lineLimit(2)
                                    }
                                    .foregroundColor(editType == option.id ? AppConstants.Colors.brandNavy : AppConstants.Colors.primaryText)
                                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                                    .padding(.horizontal, 11)
                                    .background(editType == option.id ? AppConstants.Colors.fireflyGlow : AppConstants.Colors.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(editType == option.id ? AppConstants.Colors.primaryAction : AppConstants.Colors.separator) }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(editType == option.id ? .isSelected : [])
                            }
                        }
                    }
                    TextField("What should the school know?", text: $editMessage, axis: .vertical)
                }
            }
            .navigationTitle("Edit Update")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isEditing = false } }
                ToolbarItem(placement: .confirmationAction) { Button(isSavingEdit ? "Saving…" : "Save") { saveEdits() }.disabled(isSavingEdit) }
            }
        }
    }

    private func beginEditing() {
        if let event = careEvent {
            editType = event.eventType.rawValue
            editDate = event.occurredAt
            editDetails = event.details
            editDomains = Set(event.developmentalDomains.compactMap(ChildDevelopmentalDomain.init(rawValue:)))
            editHighlight = event.reportHighlight
        } else if let request = familyRequest {
            editType = request.requestType
            editMessage = request.details["message"]?.stringValue ?? ""
        }
        isEditing = true
    }

    private func saveEdits() {
        isSavingEdit = true
        Task {
            if let event = careEvent {
                await model.updateCareEvent(event, type: ChildCareEventType(rawValue: editType) ?? event.eventType, occurredAt: editDate, details: editDetails, domains: Array(editDomains), highlight: editHighlight)
            } else if let request = familyRequest {
                var details = request.details
                details["message"] = .string(editMessage)
                await model.updateFamilyRequest(request, type: editType, details: details)
            }
            await MainActor.run { isSavingEdit = false; isEditing = false }
        }
    }

    private func detailBinding(_ key: String) -> Binding<String> {
        Binding(get: { editDetails[key]?.stringValue ?? "" }, set: { editDetails[key] = .string($0) })
    }

    @ViewBuilder
    private func editQuickPresets(for type: ChildCareEventType) -> some View {
        let values: [String] = type == .meal ? ["All", "Most", "Some", "None"] : type == .bottle ? ["2 oz", "4 oz", "6 oz", "All"] : type == .nap ? ["30 min", "1 hr", "1.5 hr", "2+ hr"] : type == .potty ? ["Successful", "Tried", "Accident"] : type == .diaper ? ["Dry", "Wet", "Bowel movement"] : []
        if !values.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        Button(value) { editDetails[type == .meal || type == .bottle ? "amount" : "outcome"] = .string(value) }
                            .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(AppConstants.Colors.background).clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func editSummaryPlaceholder(for type: ChildCareEventType) -> String {
        switch type { case .meal: "Food and notes"; case .bottle: "Bottle details"; case .nap: "Nap notes"; case .potty: "Potty notes"; case .diaper: "Diaper notes"; case .medication: "Administration notes"; case .healthCheck: "Health observation"; case .activity: "Learning activity"; case .observation: "What did you observe?"; case .kudos: "What went well?"; case .incident: "What happened?"; case .note: "Note"; case .photo: "Photo caption" }
    }

    private func saveMedia(_ url: URL) {
        Task {
            do {
                try await MediaLibrarySaver.save(remoteURL: url, contentType: mediaContentType, fileName: mediaFileName)
                await MainActor.run { mediaSaveMessage = "Saved to Photos." }
            } catch {
                await MainActor.run { mediaSaveMessage = AppErrorMessage.school("Could not save media", error) }
            }
        }
    }

    private func deleteEntry() {
        Task {
            let deleted: Bool
            if let event = careEvent { deleted = await model.deleteCareEvent(event) }
            else if let request = familyRequest { deleted = await model.deleteFamilyRequest(request) }
            else { deleted = false }
            if deleted { await MainActor.run { dismiss() } }
        }
    }
}
