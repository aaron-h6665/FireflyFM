import PhotosUI
import SwiftData
import SwiftUI

struct BoxDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MissingPieceRecord.createdAt, order: .reverse) private var allMissingPieces: [MissingPieceRecord]
    @Bindable var box: SetBox
    let set: BrickSet

    @State private var isEditing = false
    @State private var isAddingMissingPiece = false
    @State private var archiveConfirmation = false
    @State private var boxPhotoItem: PhotosPickerItem?
    @State private var receiptItem: PhotosPickerItem?

    private var missingPieces: [MissingPieceRecord] {
        allMissingPieces.filter { $0.boxID == box.id }
    }

    var body: some View {
        List {
            Section {
                if let data = box.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                PhotosPicker(selection: $boxPhotoItem, matching: .images) {
                    Label("Choose box photo", systemImage: "photo.badge.plus")
                }
            }

            Section("At a glance") {
                LabeledContent("Set", value: "#\(set.number) · \(set.name)")
                LabeledContent("Condition", value: box.condition.rawValue)
                LabeledContent("Status", value: box.status.rawValue)
                LabeledContent("Location", value: box.storageLocation.isEmpty ? "Not set" : box.storageLocation)
            }

            Section("Purchase") {
                LabeledContent("Price", value: currency(cents: box.purchasePriceCents))
                if let date = box.purchaseDate {
                    LabeledContent("Purchased", value: date.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent("Seller", value: box.seller.isEmpty ? "Not set" : box.seller)

                if let data = box.receiptData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                PhotosPicker(selection: $receiptItem, matching: .images) {
                    Label("Choose receipt image", systemImage: "doc.viewfinder")
                }
            }

            Section {
                if missingPieces.isEmpty {
                    Text("No missing pieces recorded for this box.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(missingPieces) { piece in
                        MissingPieceRow(piece: piece)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(piece.isResolved ? "Reopen" : "Found") {
                                    piece.resolvedAt = piece.isResolved ? nil : .now
                                    box.condition = missingPieces.contains(where: { !$0.isResolved && $0.id != piece.id }) ? .incomplete : .opened
                                    modelContext.insert(InventoryEvent(
                                        kind: "missing",
                                        title: piece.isResolved ? "Reopened missing piece" : "Piece found",
                                        detail: "\(piece.quantity)× \(piece.name) · \(box.label)"
                                    ))
                                    try? modelContext.save()
                                }
                                .tint(piece.isResolved ? AppTheme.yellow : AppTheme.teal)
                            }
                    }
                }

                Button {
                    isAddingMissingPiece = true
                } label: {
                    Label("Record missing piece", systemImage: "minus.circle.fill")
                }
            } header: {
                Text("Missing pieces · \(missingPieces.filter { !$0.isResolved }.reduce(0) { $0 + $1.quantity }) open")
            } footer: {
                Text("Mark pieces found instead of deleting them so the box keeps a useful history.")
            }

            if !box.notes.isEmpty {
                Section("Notes") { Text(box.notes) }
            }

            Section {
                Button("Archive this box", role: .destructive) {
                    archiveConfirmation = true
                }
            } footer: {
                Text("Archiving hides the box but preserves receipts, photos, purchase history, and missing-piece records.")
            }
        }
        .navigationTitle(box.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            BoxEditView(box: box)
        }
        .sheet(isPresented: $isAddingMissingPiece) {
            AddMissingPieceView(box: box)
        }
        .confirmationDialog("Archive \(box.label)?", isPresented: $archiveConfirmation, titleVisibility: .visible) {
            Button("Archive box", role: .destructive) {
                box.isArchived = true
                modelContext.insert(InventoryEvent(kind: "archive", title: "Archived \(set.name)", detail: box.label))
                try? modelContext.save()
            }
        } message: {
            Text("Nothing is permanently deleted. You can show archived boxes from the Sets filter.")
        }
        .task(id: boxPhotoItem) {
            if let data = try? await boxPhotoItem?.loadTransferable(type: Data.self) {
                box.photoData = data
                try? modelContext.save()
            }
        }
        .task(id: receiptItem) {
            if let data = try? await receiptItem?.loadTransferable(type: Data.self) {
                box.receiptData = data
                try? modelContext.save()
            }
        }
    }

    private func currency(cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}

private struct MissingPieceRow: View {
    let piece: MissingPieceRecord

    var body: some View {
        HStack {
            Image(systemName: piece.isResolved ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(piece.isResolved ? AppTheme.teal : AppTheme.coral)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(piece.quantity)× \(piece.name)")
                    .strikethrough(piece.isResolved)
                Text("#\(piece.partNumber) · \(piece.color)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BoxEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var box: SetBox
    @State private var priceText = ""
    @State private var hasPurchaseDate = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Box") {
                    TextField("Label", text: $box.label)
                    TextField("Storage location", text: $box.storageLocation)
                    Picker("Condition", selection: Binding(get: { box.condition }, set: { box.condition = $0 })) {
                        ForEach(BoxCondition.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Status", selection: Binding(get: { box.status }, set: { box.status = $0 })) {
                        ForEach(BoxStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Purchase") {
                    TextField("Price", text: $priceText).keyboardType(.decimalPad)
                    TextField("Seller", text: $box.seller)
                    Toggle("Purchase date", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("Date", selection: Binding(get: { box.purchaseDate ?? .now }, set: { box.purchaseDate = $0 }), displayedComponents: .date)
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $box.notes, axis: .vertical).lineLimit(3...8)
                }
            }
            .navigationTitle("Edit \(box.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        box.purchasePriceCents = Int(((Double(priceText) ?? 0) * 100).rounded())
                        if !hasPurchaseDate { box.purchaseDate = nil }
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                priceText = box.purchasePriceCents == 0 ? "" : String(format: "%.2f", Double(box.purchasePriceCents) / 100)
                hasPurchaseDate = box.purchaseDate != nil
            }
        }
    }
}

private struct AddMissingPieceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var box: SetBox
    @State private var partNumber = ""
    @State private var name = ""
    @State private var color = ""
    @State private var quantity = 1
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Piece") {
                    TextField("Part number", text: $partNumber)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Name (Plate 2 x 4)", text: $name)
                    TextField("Color", text: $color)
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }
                Section("Notes") {
                    TextField("Where you stopped, substitutions, etc.", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Missing Piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let piece = MissingPieceRecord(
                            boxID: box.id,
                            partNumber: partNumber.isEmpty ? "Unknown" : partNumber,
                            name: name.isEmpty ? "Unknown piece" : name,
                            color: color.isEmpty ? "Unknown" : color,
                            quantity: quantity,
                            notes: notes
                        )
                        modelContext.insert(piece)
                        box.condition = .incomplete
                        modelContext.insert(InventoryEvent(kind: "missing", title: "Missing piece recorded", detail: "\(quantity)× \(piece.name) · \(box.label)"))
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
