import SwiftData
import SwiftUI

struct SetDetailView: View {
    @Query(sort: \SetBox.createdAt) private var allBoxes: [SetBox]
    let set: BrickSet
    @State private var isAddingBox = false

    private var boxes: [SetBox] {
        allBoxes.filter { $0.setNumber == set.number && !$0.isArchived }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppTheme.yellow.gradient)
                            .frame(width: 76, height: 76)
                            .overlay {
                                Image(systemName: "shippingbox.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(AppTheme.navy)
                            }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(set.name)
                                .font(.title3.bold())
                            Text("#\(set.number) · \(set.theme)")
                                .foregroundStyle(.secondary)
                            Text("\(boxes.count) physical \(boxes.count == 1 ? "box" : "boxes")")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    HStack {
                        spec("Year", "\(set.year)")
                        spec("Ages", set.age)
                        spec("Parts", set.partCount.formatted())
                    }

                    Link(destination: set.instructionsURL) {
                        Label("Open official instructions", systemImage: "book.pages.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            }

            Section("Physical boxes") {
                ForEach(boxes) { box in
                    NavigationLink {
                        BoxDetailView(box: box, set: set)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(box.label)
                                    .font(.headline)
                                Spacer()
                                Text(box.condition.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(box.condition == .incomplete ? AppTheme.coral : AppTheme.teal)
                            }
                            Text(box.storageLocation.isEmpty ? "Location not set" : box.storageLocation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button {
                    isAddingBox = true
                } label: {
                    Label("Add another box", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle(set.number)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAddingBox) {
            NavigationStack {
                AddBoxView(set: set) { isAddingBox = false }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isAddingBox = false }
                        }
                    }
            }
        }
    }

    private func spec(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
