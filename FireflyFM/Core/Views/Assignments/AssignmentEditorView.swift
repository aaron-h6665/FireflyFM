//
//  AssignmentEditorView.swift
//  FireflyFM
//

import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct AssignmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let assignment: Assignment
    var onSaved: () -> Void

    private let materialDraftStore = AssignmentDraftAttachmentStore()

    @State private var model = AssignmentEditorModel()
    @State private var title: String
    @State private var description: String
    @State private var hasDueDate: Bool
    @State private var dueAt: Date
    @State private var allowResubmission: Bool
    @State private var materials: [AssignmentMaterialUpdate]
    @State private var showingMaterialImporter = false
    @State private var replacingMaterialId: UUID?
    @State private var materialDraftId = UUID()
    @State private var importError: String?
    @State private var previewURL: URL?
    @State private var webURL: URL?

    init(assignment: Assignment, materials: [AssignmentMaterial], onSaved: @escaping () -> Void) {
        self.assignment = assignment
        self.onSaved = onSaved
        _title = State(initialValue: assignment.title)
        _description = State(initialValue: assignment.description ?? "")
        _hasDueDate = State(initialValue: assignment.dueAt != nil)
        _dueAt = State(initialValue: assignment.dueAt ?? Date().addingTimeInterval(7 * 24 * 60 * 60))
        _allowResubmission = State(initialValue: assignment.allowResubmission ?? true)
        _materials = State(initialValue: materials.map(AssignmentMaterialUpdate.init(material:)))
    }

    private var canSave: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && materials.allSatisfy(materialIsValid)
            && model.isSaving == false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Assignment details") {
                    labeledField("Title") {
                        TextField("Enter assignment title", text: $title)
                    }
                    labeledField("Description / instructions") {
                        TextField("Explain what recipients need to do", text: $description, axis: .vertical)
                            .lineLimit(3...8)
                    }
                }

                Section("Due date") {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due date and time", selection: $dueAt)
                    }
                }

                Section("Submission revisions") {
                    Toggle("Allow revised attempts", isOn: $allowResubmission)
                    Text("When enabled, a recipient can submit a new version only after you request changes. Earlier attempts remain visible for audit history.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Materials") {
                    if materials.isEmpty {
                        Text("No materials attached.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ForEach($materials) { $material in
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Type", selection: $material.materialType) {
                                Text("Article").tag("article")
                                Text("Link").tag("link")
                                Text("Picture").tag("image")
                                Text("Video").tag("video")
                                Text("File").tag("file")
                                Text("Mixed").tag("mixed")
                            }
                            labeledField("Display title") {
                                TextField("Material title", text: $material.title)
                            }
                            if isLinkMaterial(material) {
                                labeledField("Web address") {
                                    TextField("https://…", text: Binding(
                                        get: { material.url ?? "" },
                                        set: { material.url = $0 }
                                    ))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                }
                                if let value = material.url, let url = URL(string: value), value.isEmpty == false {
                                    Button("Preview Link") { webURL = url }
                                }
                            } else {
                                Label(material.localFileURL?.lastPathComponent ?? material.fileName ?? "Attached file", systemImage: "paperclip")
                                    .font(.subheadline)
                                HStack {
                                    if material.privateFilePath != nil && material.localFileURL == nil {
                                        Button("Preview") { preview(material) }
                                    }
                                    Menu("Replace File") {
                                        ForEach(AssignmentFileImportSource.allCases) { source in
                                            Button {
                                                replacingMaterialId = material.id
                                                showingMaterialImporter = true
                                            } label: {
                                                Label(source.title, systemImage: source.systemImage)
                                            }
                                        }
                                    }
                                }
                            }
                            Button("Remove Material", role: .destructive) {
                                removeMaterial(material)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    Button {
                        materials.append(AssignmentMaterialUpdate(materialType: "link", title: "", url: ""))
                    } label: {
                        Label("Add Link", systemImage: "link.badge.plus")
                    }
                    Menu {
                        ForEach(AssignmentFileImportSource.allCases) { source in
                            Button {
                                replacingMaterialId = nil
                                showingMaterialImporter = true
                            } label: {
                                Label(source.title, systemImage: source.systemImage)
                            }
                        }
                    } label: {
                        Label("Add Files", systemImage: "paperclip")
                    }
                    .accessibilityIdentifier("assignment-editor-material-source-menu")
                    if let help = AssignmentFileImportSource.googleDrive.pickerHelp {
                        Text(help)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let errorMessage = importError ?? model.errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Edit Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        removeAllImportedMaterials()
                        dismiss()
                    }
                    .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? "Saving…" : "Save") { save() }
                        .disabled(canSave == false)
                }
            }
            .fileImporter(isPresented: $showingMaterialImporter, allowedContentTypes: [.item], allowsMultipleSelection: replacingMaterialId == nil) { result in
                do {
                    guard let ownerId = appSession.profile?.id else {
                        importError = "Could not attach the selected material because your account is unavailable."
                        return
                    }
                    let importedURLs = try materialDraftStore.add(
                        try result.get(),
                        for: materialDraftId,
                        ownerId: ownerId
                    )
                    if let replacingMaterialId, let url = importedURLs.first,
                       let index = materials.firstIndex(where: { $0.id == replacingMaterialId }) {
                        removeImportedFile(materials[index].localFileURL)
                        materials[index].localFileURL = url
                        materials[index].url = nil
                        materials[index].privateFilePath = nil
                        materials[index].fileName = url.lastPathComponent
                    } else {
                        materials.append(contentsOf: importedURLs.map {
                            AssignmentMaterialUpdate(materialType: "file", title: $0.deletingPathExtension().lastPathComponent, fileName: $0.lastPathComponent, localFileURL: $0)
                        })
                    }
                    importError = nil
                } catch where AppErrorMessage.isCancellation(error) {
                } catch {
                    importError = AppErrorMessage.school("Could not attach the selected material", error)
                }
                self.replacingMaterialId = nil
            }
            .sheet(isPresented: Binding(get: { webURL != nil }, set: { if !$0 { webURL = nil } })) {
                if let webURL { AssignmentSafariView(url: webURL).ignoresSafeArea() }
            }
            .quickLookPreview($previewURL)
            .interactiveDismissDisabled(model.isSaving)
            .onDisappear { removeAllImportedMaterials() }
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.bold()).foregroundColor(.secondary)
            content()
        }
    }

    private func isLinkMaterial(_ material: AssignmentMaterialUpdate) -> Bool {
        material.localFileURL == nil && material.privateFilePath == nil
    }

    private func materialIsValid(_ material: AssignmentMaterialUpdate) -> Bool {
        if isLinkMaterial(material) {
            guard let value = material.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
            return true
        }
        return material.localFileURL != nil || material.privateFilePath != nil
    }

    private func removeMaterial(_ material: AssignmentMaterialUpdate) {
        removeImportedFile(material.localFileURL)
        materials.removeAll { $0.id == material.id }
    }

    private func removeImportedFile(_ url: URL?) {
        guard let url, let ownerId = appSession.profile?.id else { return }
        try? materialDraftStore.remove(url, for: materialDraftId, ownerId: ownerId)
    }

    private func removeAllImportedMaterials() {
        guard let ownerId = appSession.profile?.id else { return }
        try? materialDraftStore.removeAll(for: materialDraftId, ownerId: ownerId)
    }

    private func preview(_ material: AssignmentMaterialUpdate) {
        guard let path = material.privateFilePath else { return }
        Task {
            if let destination = await model.previewURL(
                path: path,
                preferredName: material.fileName ?? "material"
            ) {
                previewURL = destination
            }
        }
    }

    private func save() {
        Task {
            let saved = await model.save(AssignmentEditDraft(
                    assignment: assignment,
                    title: title,
                    description: description.isEmpty ? nil : description,
                    dueAt: hasDueDate ? dueAt : nil,
                    allowResubmission: allowResubmission,
                    materials: materials
                ))
            if saved {
                removeAllImportedMaterials()
                onSaved()
                dismiss()
            }
        }
    }
}
