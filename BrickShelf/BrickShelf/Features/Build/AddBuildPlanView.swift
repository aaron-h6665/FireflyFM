import SwiftData
import SwiftUI

struct AddBuildPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var setNumber = ""
    @State private var source = PlanSource.custom
    @State private var creator = ""
    @State private var instructionsURL = ""
    @State private var requirementsText = ""

    private var requirements: [PartRequirement] {
        requirementsText.split(whereSeparator: \String.Element.isNewline).compactMap { line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard fields.count >= 4, let quantity = Int(fields[3]), quantity > 0 else { return nil }
            return PartRequirement(partNumber: fields[0], name: fields[1], color: fields[2], quantity: quantity)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("Name", text: $name)
                    TextField("Set or plan number", text: $setNumber)
                    Picker("Source", selection: $source) {
                        ForEach(PlanSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Creator / publisher", text: $creator)
                    TextField("Instructions URL", text: $instructionsURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                Section {
                    TextEditor(text: $requirementsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                } header: {
                    Text("Parts")
                } footer: {
                    Text("One per line: part number, name, color, quantity\nExample: 3001, Brick 2 x 4, Red, 12")
                }

                Section("Preview") {
                    LabeledContent("Part groups", value: requirements.count.formatted())
                    LabeledContent("Total pieces", value: requirements.reduce(0) { $0 + $1.quantity }.formatted())
                }
            }
            .navigationTitle("New Build Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let plan = BuildPlanRecord(
                            setNumber: setNumber.isEmpty ? "CUSTOM" : setNumber,
                            name: name,
                            source: source,
                            creator: creator.isEmpty ? "Unknown creator" : creator,
                            instructionsURLString: instructionsURL,
                            requirements: requirements,
                            isCompleteInventory: true
                        )
                        modelContext.insert(plan)
                        modelContext.insert(InventoryEvent(kind: "plan", title: "Added build plan", detail: plan.name))
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || requirements.isEmpty)
                }
            }
        }
    }
}
