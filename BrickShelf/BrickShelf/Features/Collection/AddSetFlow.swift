import SwiftData
import SwiftUI

struct AddSetFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isScanning = false
    @State private var scannedSet: BrickSet?
    @State private var scanMessage: String?

    private var results: [BrickSet] { SetCatalog.search(searchText) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isScanning = true
                    } label: {
                        Label("Scan set barcode or QR", systemImage: "barcode.viewfinder")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)

                    if let scanMessage {
                        Text(scanMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Package UPC lookup needs a catalog provider. This prototype recognizes supported set numbers and LEGO instruction QR links, then falls back to search.")
                }

                Section("Catalog") {
                    ForEach(results) { set in
                        NavigationLink(value: set) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(set.name)
                                    .font(.headline)
                                Text("#\(set.number) · \(set.year) · \(set.partCount.formatted()) pieces")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Add a Set")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Set number or name")
            .navigationDestination(for: BrickSet.self) { set in
                AddBoxView(set: set) {
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isScanning) {
                BarcodeScannerSheet { value in
                    isScanning = false
                    if let number = SetCatalog.setNumber(fromScannedValue: value),
                       let match = SetCatalog.item(number: number) {
                        scannedSet = match
                    } else {
                        searchText = value
                        scanMessage = "That code is not in the prototype catalog. Search or enter the set number instead."
                    }
                }
            }
            .navigationDestination(item: $scannedSet) { set in
                AddBoxView(set: set) {
                    dismiss()
                }
            }
        }
    }
}

struct AddBoxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBoxes: [SetBox]
    let set: BrickSet
    let onSaved: () -> Void

    @State private var label = ""
    @State private var location = ""
    @State private var condition = BoxCondition.opened
    @State private var status = BoxStatus.stored
    @State private var priceText = ""
    @State private var seller = ""
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date.now
    @State private var notes = ""

    private var suggestedLabel: String {
        let count = allBoxes.filter { $0.setNumber == set.number }.count
        return "Box \(count + 1)"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Set", value: set.name)
                LabeledContent("Number", value: set.number)
                LabeledContent("Parts", value: set.partCount.formatted())
            } header: {
                Text("Set details")
            }

            Section("This physical box") {
                TextField(suggestedLabel, text: $label)
                TextField("Storage location (Shelf 2, closet)", text: $location)
                Picker("Condition", selection: $condition) {
                    ForEach(BoxCondition.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Status", selection: $status) {
                    ForEach(BoxStatus.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section("Purchase — kept with this box") {
                TextField("Price", text: $priceText)
                    .keyboardType(.decimalPad)
                TextField("Seller", text: $seller)
                Toggle("Add purchase date", isOn: $hasPurchaseDate)
                if hasPurchaseDate {
                    DatePicker("Date", selection: $purchaseDate, displayedComponents: .date)
                }
            }

            Section("Notes") {
                TextField("Anything useful later", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("Add \(suggestedLabel)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            if label.isEmpty { label = suggestedLabel }
        }
    }

    private func save() {
        let cents = Int(((Double(priceText) ?? 0) * 100).rounded())
        let box = SetBox(
            setNumber: set.number,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? suggestedLabel : label,
            storageLocation: location,
            condition: condition,
            status: status,
            purchasePriceCents: cents,
            purchaseDate: hasPurchaseDate ? purchaseDate : nil,
            seller: seller,
            notes: notes
        )
        modelContext.insert(box)
        modelContext.insert(InventoryEvent(kind: "box", title: "Added \(set.name)", detail: "\(box.label) · \(box.storageLocation.isEmpty ? "Location not set" : box.storageLocation)"))
        try? modelContext.save()
        onSaved()
    }
}
