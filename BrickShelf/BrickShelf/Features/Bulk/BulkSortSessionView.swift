import PhotosUI
import SwiftData
import SwiftUI

struct BulkSortSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorageBin.code) private var bins: [StorageBin]
    @Query private var allBulk: [BulkPieceRecord]

    @State private var partNumber = ""
    @State private var name = ""
    @State private var color = ""
    @State private var quantity = 1
    @State private var binCode = ""
    @State private var notes = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var savedCount = 0
    @FocusState private var focusedField: SortField?

    private enum SortField { case partNumber, name }
    private let commonPieces = ["Brick 2 x 4", "Brick 1 x 2", "Plate 2 x 4", "Tile 1 x 2", "Technic Pin"]
    private let commonColors = ["Black", "White", "Red", "Blue", "Light Gray", "Dark Gray", "Tan"]

    private var suggestedBin: StorageBin? {
        let lowercased = name.lowercased()
        if lowercased.contains("plate") || lowercased.contains("tile") {
            return bins.first { $0.code == "A1" }
        }
        if lowercased.contains("technic") || lowercased.contains("pin") || lowercased.contains("axle") {
            return bins.first { $0.code == "B1" }
        }
        if lowercased.contains("brick") {
            return bins.first { $0.code == "A2" }
        }
        return bins.first { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Piece \(savedCount + 1)")
                                .font(.title2.bold())
                            Text("Keep the bin; change only what differs.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if savedCount > 0 {
                            Text("\(savedCount) saved")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.teal)
                        }
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Identify").font(.headline)
                        TextField("Part number", text: $partNumber)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($focusedField, equals: .partNumber)
                        TextField("Piece name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .name)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(commonPieces, id: \.self) { piece in
                                    Button(piece) { name = piece }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }

                        TextField("Color", text: $color)
                            .textFieldStyle(.roundedBorder)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(commonColors, id: \.self) { value in
                                    Button(value) { color = value }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Count").font(.headline)
                        HStack(spacing: 12) {
                            Button { quantity = max(1, quantity - 1) } label: {
                                Image(systemName: "minus").frame(width: 42, height: 42)
                            }
                            .buttonStyle(.bordered)
                            Text(quantity.formatted())
                                .font(.title.bold())
                                .monospacedDigit()
                                .frame(minWidth: 70)
                            Button { quantity += 1 } label: {
                                Image(systemName: "plus").frame(width: 42, height: 42)
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                            ForEach([10, 25, 50], id: \.self) { value in
                                Button("+\(value)") { quantity += value }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Put it away").font(.headline)
                        Picker("Bin", selection: $binCode) {
                            Text("Choose a bin").tag("")
                            ForEach(bins.filter { !$0.isArchived }) { bin in
                                Text("\(bin.code) · \(bin.name)").tag(bin.code)
                            }
                        }
                        .pickerStyle(.menu)

                        if let suggestedBin, suggestedBin.code != binCode {
                            Button {
                                binCode = suggestedBin.code
                            } label: {
                                Label("Suggested: \(suggestedBin.code) · \(suggestedBin.name)", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.bordered)
                        }

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Choose reference photo", systemImage: "camera.fill")
                        }
                        TextField("Optional note", text: $notes)
                            .textFieldStyle(.roundedBorder)
                    }
                    .appCard()

                    Button {
                        saveAndContinue()
                    } label: {
                        Label("Save and next piece", systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || color.trimmingCharacters(in: .whitespaces).isEmpty || binCode.isEmpty)
                }
                .padding()
            }
            .background(AppTheme.canvas)
            .navigationTitle("Sort Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                binCode = bins.first(where: { !$0.isArchived })?.code ?? ""
                focusedField = .partNumber
            }
            .onChange(of: name) { _, _ in
                if let suggestedBin, binCode.isEmpty { binCode = suggestedBin.code }
            }
            .task(id: photoItem) {
                photoData = try? await photoItem?.loadTransferable(type: Data.self)
            }
        }
    }

    private func saveAndContinue() {
        let normalizedNumber = partNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : partNumber
        if let existing = allBulk.first(where: {
            !$0.isArchived
                && $0.partNumber.caseInsensitiveCompare(normalizedNumber) == .orderedSame
                && $0.color.caseInsensitiveCompare(color) == .orderedSame
                && $0.binCode.caseInsensitiveCompare(binCode) == .orderedSame
        }) {
            existing.quantity += quantity
            existing.updatedAt = .now
            if !notes.isEmpty { existing.notes = notes }
            if let photoData { existing.photoData = photoData }
        } else {
            modelContext.insert(BulkPieceRecord(
                partNumber: normalizedNumber,
                name: name,
                color: color,
                quantity: quantity,
                binCode: binCode,
                notes: notes,
                photoData: photoData
            ))
        }
        modelContext.insert(InventoryEvent(kind: "bulk", title: "Sorted \(quantity) pieces", detail: "\(name) · \(color) → \(binCode)"))
        try? modelContext.save()

        savedCount += 1
        partNumber = ""
        name = ""
        color = ""
        quantity = 1
        notes = ""
        photoItem = nil
        photoData = nil
        focusedField = .partNumber
    }
}
