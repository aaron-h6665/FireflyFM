import SwiftUI
import Supabase

struct PaperworkCorrectionDraft: Codable, Identifiable {
    var target_kind: String
    var target_id: String
    var title: String
    var note: String
    var id: String { "\(target_kind):\(target_id)" }
}

struct CorrectionTargetEditor: View {
    let kind: String
    let target: String
    let title: String
    @Binding var corrections: [PaperworkCorrectionDraft]
    private var index: Int? { corrections.firstIndex { $0.target_kind == kind && $0.target_id == target } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if let index { corrections.remove(at: index) }
                else { corrections.append(.init(target_kind: kind, target_id: target, title: title, note: "")) }
            } label: {
                Label(
                    index == nil ? "Mark this answer for correction" : "Remove correction request",
                    systemImage: index == nil ? "square" : "checkmark.square.fill"
                )
            }
            .font(FireflyTheme.Typography.body)
            .buttonStyle(.borderless)
            if index != nil {
                TextField("What needs to change?", text: Binding(
                    get: { index.map { corrections[$0].note } ?? "" },
                    set: { value in if let index { corrections[index].note = value } }
                ), axis: .vertical)
                .padding(8).background(FireflyTheme.Colors.raised, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct CorrectionChecklist: View {
    let googleImportId: UUID?
    let submissionId: UUID?
    @State private var corrections: [PaperworkCorrectionDraft] = []
    @State private var error: String?
    var body: some View {
        Section("Requested corrections") {
            ForEach(corrections) { correction in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "square")
                        .font(.title3)
                        .foregroundStyle(FireflyTheme.Colors.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(correction.title)
                            .font(FireflyTheme.Typography.rowTitle)
                            .foregroundStyle(FireflyTheme.Colors.primaryText)
                        Text(correction.note)
                            .font(FireflyTheme.Typography.body)
                            .foregroundStyle(FireflyTheme.Colors.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("To do: \(correction.title). \(correction.note)")
            }
            if let error { FireflyInlineError(message: error) }
            if corrections.isEmpty && error == nil {
                Label("No corrections requested", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(FireflyTheme.Colors.success)
            }
        }
        .task(id: googleImportId ?? submissionId) {
            do {
                guard let id = googleImportId ?? submissionId else { return }
                corrections = try await AppConstants.supabase.from("paperwork_corrections")
                    .select("target_kind,target_id,title,note")
                    .eq(googleImportId != nil ? "google_import_id" : "submission_id", value: id)
                    .order("created_at").execute().value
            } catch { self.error = AppErrorMessage.school("Could not load corrections", error) }
        }
    }
}

struct GoogleCorrectionReviewParams: Encodable {
    let input_import_id: UUID
    let input_decision: String
    let input_matched_child_id: UUID?
    let input_review_note: String?
    let input_corrections: [PaperworkCorrectionDraft]
}

struct NativeCorrectionReviewParams: Encodable {
    let input_submission_id: UUID
    let input_decision: String
    let input_message: String?
    let input_corrections: [PaperworkCorrectionDraft]
}

struct PaperworkFileButton: View {
    let name: String
    let path: String?
    @State private var url: URL?
    @State private var showing = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading) {
            Button {
                Task {
                    do {
                        guard let path else { return }
                        url = try await SchoolService.shared.signedPrivateFileURL(path: path)
                        showing = true
                    } catch { self.error = AppErrorMessage.school("Could not open file", error) }
                }
            } label: { Label(name, systemImage: "doc.fill") }
            .disabled(path == nil)
            if path == nil { Text("File is unavailable; a replacement may be needed.").font(.caption).foregroundStyle(.secondary) }
            if let error { FireflyInlineError(message: error) }
        }
        .sheet(isPresented: $showing) { if let url { FireflySafariView(url: url).ignoresSafeArea() } }
    }
}

struct PaperworkResponseHistory: View {
    let requirementId: UUID
    @State private var responses: [GoogleFormImport] = []
    @State private var error: String?
    var body: some View {
        Form {
            ForEach(responses) { response in
                Section(response.responseSubmittedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Submission") {
                    Text(response.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.headline)
                    ForEach(response.displayedAnswers) { LabeledContent($0.title, value: $0.value) }
                    if let note = response.reviewNote { Text(note) }
                }
                CorrectionChecklist(googleImportId: response.id, submissionId: nil)
            }
            if let error { FireflyInlineError(message: error) }
            if responses.isEmpty && error == nil { Text("No earlier submissions.") }
        }
        .navigationTitle("Submission history")
        .task {
            struct Params: Encodable { let input_requirement_id: UUID }
            do { responses = try await AppConstants.supabase.rpc("fetch_paperwork_response_history", params: Params(input_requirement_id: requirementId)).execute().value }
            catch { self.error = AppErrorMessage.school("Could not load history", error) }
        }
    }
}
