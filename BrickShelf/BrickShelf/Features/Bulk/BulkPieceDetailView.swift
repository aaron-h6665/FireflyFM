import SwiftData
import SwiftUI

struct BulkPieceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var piece: BulkPieceRecord
    @State private var archiveConfirmation = false

    var body: some View {
        Form {
            Section("Piece") {
                TextField("Part number", text: $piece.partNumber)
                TextField("Name", text: $piece.name)
                TextField("Color", text: $piece.color)
            }

            Section("Quantity") {
                HStack {
                    Button { adjust(by: -1) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                    Spacer()
                    Text(piece.quantity.formatted())
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                    Spacer()
                    Button { adjust(by: 1) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                }
                .buttonStyle(.plain)
                Stepper("Adjust by 10", value: $piece.quantity, in: 0...99_999, step: 10)
            }

            Section("Find it again") {
                TextField("Bin code", text: $piece.binCode)
                TextField("Notes", text: $piece.notes, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section {
                Button("Archive this inventory line", role: .destructive) {
                    archiveConfirmation = true
                }
            } footer: {
                Text("Use quantity changes for normal counting. Archive only duplicate or invalid records; the activity log preserves the action.")
            }
        }
        .navigationTitle(piece.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            piece.updatedAt = .now
            try? modelContext.save()
        }
        .confirmationDialog("Archive this line?", isPresented: $archiveConfirmation) {
            Button("Archive", role: .destructive) {
                piece.isArchived = true
                modelContext.insert(InventoryEvent(kind: "archive", title: "Archived bulk record", detail: "\(piece.name) · \(piece.color)"))
                try? modelContext.save()
            }
        }
    }

    private func adjust(by amount: Int) {
        let oldValue = piece.quantity
        piece.quantity = max(0, piece.quantity + amount)
        piece.updatedAt = .now
        modelContext.insert(InventoryEvent(kind: "quantity", title: "Adjusted \(piece.name)", detail: "\(oldValue) → \(piece.quantity) in \(piece.binCode)"))
        try? modelContext.save()
    }
}
