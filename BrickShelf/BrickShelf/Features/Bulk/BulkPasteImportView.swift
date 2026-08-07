import SwiftData
import SwiftUI

struct BulkPasteImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allBulk: [BulkPieceRecord]
    @State private var text = ""
    @State private var errorMessage: String?

    private struct ParsedRow {
        let partNumber: String
        let name: String
        let color: String
        let quantity: Int
        let bin: String
    }

    private var rows: [ParsedRow] {
        text.split(whereSeparator: \String.Element.isNewline).compactMap { line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard fields.count >= 5, let quantity = Int(fields[3]), quantity > 0 else { return nil }
            return ParsedRow(partNumber: fields[0], name: fields[1], color: fields[2], quantity: quantity, bin: fields[4])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 220)
                } header: {
                    Text("One piece group per line")
                } footer: {
                    Text("Format: part number, name, color, quantity, bin\nExample: 3001, Brick 2 x 4, Red, 20, A2")
                }

                Section("Preview") {
                    LabeledContent("Valid rows", value: rows.count.formatted())
                    LabeledContent("Pieces", value: rows.reduce(0) { $0 + $1.quantity }.formatted())
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Paste Bulk List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importRows() }
                        .disabled(rows.isEmpty)
                }
            }
        }
    }

    private func importRows() {
        for row in rows {
            if let existing = allBulk.first(where: {
                !$0.isArchived
                    && $0.partNumber.caseInsensitiveCompare(row.partNumber) == .orderedSame
                    && $0.color.caseInsensitiveCompare(row.color) == .orderedSame
                    && $0.binCode.caseInsensitiveCompare(row.bin) == .orderedSame
            }) {
                existing.quantity += row.quantity
                existing.updatedAt = .now
            } else {
                modelContext.insert(BulkPieceRecord(
                    partNumber: row.partNumber,
                    name: row.name,
                    color: row.color,
                    quantity: row.quantity,
                    binCode: row.bin
                ))
            }
        }
        modelContext.insert(InventoryEvent(kind: "bulk", title: "Imported bulk list", detail: "\(rows.count) groups · \(rows.reduce(0) { $0 + $1.quantity }) pieces"))
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
