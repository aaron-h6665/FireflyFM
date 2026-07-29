//
//  AssignmentEditorView.swift
//  FireflyFM
//

import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct AssignmentEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let assignment: Assignment
    var onSaved: () -> Void

    @State private var title: String
    @State private var description: String
    @State private var hasDueDate: Bool
    @State private var dueAt: Date
    @State private var allowResubmission: Bool
    @State private var materials: [AssignmentMaterialUpdate]
    @State private var showingMaterialImporter = false
    @State private var replacingMaterialId: UUID?
    @State private var previewURL: URL?
    @State private var webURL: URL?
    @State private var isSaving = false
    @State private var errorMessage: String?

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
            && isSaving == false
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
                                    Button("Replace File") {
                                        replacingMaterialId = material.id
                                        showingMaterialImporter = true
                                    }
                                }
                            }
                            Button("Remove Material", role: .destructive) {
                                materials.removeAll { $0.id == material.id }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    Button {
                        materials.append(AssignmentMaterialUpdate(materialType: "link", title: "", url: ""))
                    } label: {
                        Label("Add Link", systemImage: "link.badge.plus")
                    }
                    Button {
                        replacingMaterialId = nil
                        showingMaterialImporter = true
                    } label: {
                        Label("Add Files", systemImage: "paperclip")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .navigationTitle("Edit Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(canSave == false)
                }
            }
            .fileImporter(isPresented: $showingMaterialImporter, allowedContentTypes: [.item], allowsMultipleSelection: replacingMaterialId == nil) { result in
                guard let urls = try? result.get() else { return }
                if let replacingMaterialId, let url = urls.first,
                   let index = materials.firstIndex(where: { $0.id == replacingMaterialId }) {
                    materials[index].localFileURL = url
                    materials[index].url = nil
                    materials[index].privateFilePath = nil
                    materials[index].fileName = url.lastPathComponent
                } else {
                    materials.append(contentsOf: urls.map {
                        AssignmentMaterialUpdate(materialType: "file", title: $0.deletingPathExtension().lastPathComponent, fileName: $0.lastPathComponent, localFileURL: $0)
                    })
                }
                self.replacingMaterialId = nil
            }
            .sheet(isPresented: Binding(get: { webURL != nil }, set: { if !$0 { webURL = nil } })) {
                if let webURL { AssignmentSafariView(url: webURL).ignoresSafeArea() }
            }
            .quickLookPreview($previewURL)
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

    private func preview(_ material: AssignmentMaterialUpdate) {
        guard let path = material.privateFilePath else { return }
        Task {
            do {
                let signedURL = try await SchoolService.shared.signedPrivateFileURL(path: path)
                let destination = try await AssignmentPreviewLoader.download(
                    from: signedURL,
                    preferredName: material.fileName ?? "material"
                )
                await MainActor.run { previewURL = destination }
            } catch {
                await MainActor.run { errorMessage = AppErrorMessage.school("Could not preview material", error) }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await SchoolWorkflowService.shared.updateAssignment(
                    assignment: assignment,
                    title: title,
                    description: description.isEmpty ? nil : description,
                    dueAt: hasDueDate ? dueAt : nil,
                    allowResubmission: allowResubmission,
                    materials: materials
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not edit assignment", error)
                }
            }
        }
    }
}
