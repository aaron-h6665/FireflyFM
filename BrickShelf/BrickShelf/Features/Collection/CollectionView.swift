import SwiftData
import SwiftUI

struct CollectionView: View {
    @Query(sort: \SetBox.createdAt, order: .reverse) private var boxes: [SetBox]
    @Query private var missingPieces: [MissingPieceRecord]
    @State private var searchText = ""
    @State private var isAddingSet = false
    @State private var showArchived = false

    private var visibleBoxes: [SetBox] {
        boxes.filter { box in
            (showArchived || !box.isArchived)
                && (searchText.isEmpty
                    || box.setNumber.localizedStandardContains(searchText)
                    || box.label.localizedCaseInsensitiveContains(searchText)
                    || SetCatalog.item(number: box.setNumber)?.name.localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    private var groupedSets: [(BrickSet, [SetBox])] {
        Dictionary(grouping: visibleBoxes, by: \SetBox.setNumber)
            .compactMap { number, boxes in
                guard let set = SetCatalog.item(number: number) else { return nil }
                return (set, boxes.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending })
            }
            .sorted { $0.0.number.localizedStandardCompare($1.0.number) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groupedSets.isEmpty {
                    EmptyStateCard(
                        title: searchText.isEmpty ? "Your shelf is ready" : "No matching sets",
                        message: searchText.isEmpty ? "Scan or search for a set, then add its first physical box." : "Try a set number, name, label, or theme.",
                        systemImage: "shippingbox"
                    )
                    .padding()
                } else {
                    List {
                        ForEach(groupedSets, id: \.0.number) { set, setBoxes in
                            NavigationLink(value: set) {
                                SetGroupRow(
                                    set: set,
                                    boxes: setBoxes,
                                    openMissingCount: missingPieces.filter { record in
                                        setBoxes.contains(where: { $0.id == record.boxID }) && !record.isResolved
                                    }.reduce(0) { $0 + $1.quantity }
                                )
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("My Sets")
            .searchable(text: $searchText, prompt: "Set, theme, or box label")
            .navigationDestination(for: BrickSet.self) { set in
                SetDetailView(set: set)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Show archived boxes", isOn: $showArchived)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingSet = true
                    } label: {
                        Label("Add set", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingSet) {
                AddSetFlow()
            }
        }
    }
}

private struct SetGroupRow: View {
    let set: BrickSet
    let boxes: [SetBox]
    let openMissingCount: Int

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.blue.gradient)
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "shippingbox.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(set.name)
                    .font(.headline)
                Text("#\(set.number) · \(set.theme)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(boxes.count) \(boxes.count == 1 ? "box" : "boxes")", systemImage: "shippingbox")
                    if openMissingCount > 0 {
                        Label("\(openMissingCount) missing", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.coral)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }
}
