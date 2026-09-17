import SwiftUI
import Supabase

struct HQZelleSettingsView: View {
    @State private var name = ""
    @State private var type = "email"
    @State private var value = ""
    @State private var prefix = "HQ"
    @State private var instructions = ""
    @State private var active = false
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    struct Profile: Decodable {
        let recipient_display_name: String; let recipient_type: String; let recipient_value: String
        let memo_prefix: String; let payment_instructions: String?; let active: Bool
    }
    struct Params: Encodable {
        let input_display_name: String; let input_type: String; let input_value: String
        let input_memo_prefix: String; let input_instructions: String; let input_active: Bool
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("HQ receiving account") {
                    TextField("Recipient name", text: $name)
                    Picker("Receive using", selection: $type) { Text("Email").tag("email"); Text("Mobile").tag("mobile") }
                    TextField("Zelle recipient", text: $value).textInputAutocapitalization(.never)
                    TextField("Memo prefix", text: $prefix)
                    TextField("Instructions", text: $instructions, axis: .vertical)
                    Toggle("Accept director payments", isOn: $active)
                }
                Section { Text("Director fees use these instructions. Existing invoices retain their original recipient. Verify transfers in HQ’s bank before approving.").font(.caption) }
                if let error { FireflyInlineError(message: error) }
            }
            .disabled(loading || saving)
            .navigationTitle("HQ Zelle Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(loading || saving || name.trimmed.isEmpty || value.trimmed.isEmpty) }
            }
            .task {
                defer { loading = false }
                do {
                    let rows: [Profile] = try await AppConstants.supabase.from("hq_zelle_profile").select().execute().value
                    if let p = rows.first { name = p.recipient_display_name; type = p.recipient_type; value = p.recipient_value; prefix = p.memo_prefix; instructions = p.payment_instructions ?? ""; active = p.active }
                } catch { self.error = AppErrorMessage.school("Could not load HQ settings", error) }
            }
        }
    }
    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        do {
            _ = try await AppConstants.supabase.rpc("save_hq_zelle_profile", params: Params(input_display_name: name, input_type: type, input_value: value, input_memo_prefix: prefix, input_instructions: instructions, input_active: active)).execute()
            dismiss()
        } catch { self.error = AppErrorMessage.school("Could not save HQ settings", error) }
    }
}
