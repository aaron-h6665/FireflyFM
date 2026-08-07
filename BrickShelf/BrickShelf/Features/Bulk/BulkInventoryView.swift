import SwiftData
import SwiftUI

struct BulkInventoryView: View {
    @Query(sort: \BulkPieceRecord.updatedAt, order: .reverse) private var bulk: [BulkPieceRecord]
    @Query(sort: \StorageBin.code) private var bins: [StorageBin]
    @State private var searchText = ""
    @State private var isSorting = false
    @State private var isPasting = false
    @State private var showBinMap = false

    private var activeBulk: [BulkPieceRecord] {
        bulk.filter { piece in
            !piece.isArchived && piece.quantity > 0
                && (searchText.isEmpty
                    || piece.partNumber.localizedStandardContains(searchText)
                    || piece.name.localizedCaseInsensitiveContains(searchText)
                    || piece.color.localizedCaseInsensitiveContains(searchText)
                    || piece.binCode.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var totalPieces: Int { activeBulk.reduce(0) { $0 + $1.quantity } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(totalPieces.formatted())
                                    .font(.largeTitle.bold())
                                    .monospacedDigit()
                                Text("loose pieces in \(Set(activeBulk.map(\.binCode)).count) locations")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.3.layers.3d.top.filled")
                                .font(.system(size: 38))
                                .foregroundStyle(AppTheme.teal)
                        }

                        HStack {
                            Button {
                                isSorting = true
                            } label: {
                                Label("Start sorting", systemImage: "arrow.right.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                isPasting = true
                            } label: {
                                Label("Paste list", systemImage: "doc.on.clipboard")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    Button {
                        showBinMap = true
                    } label: {
                        HStack {
                            Label("Storage map", systemImage: "map.fill")
                            Spacer()
                            Text("\(bins.filter { !$0.isArchived }.count) bins")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Every piece needs a findable home. Bin codes stay visible in search results and build plans.")
                }

                Section("Pieces") {
                    if activeBulk.isEmpty {
                        Text("No pieces match this search.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeBulk) { piece in
                            NavigationLink {
                                BulkPieceDetailView(piece: piece)
                            } label: {
                                BulkPieceRow(piece: piece)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bulk Pieces")
            .searchable(text: $searchText, prompt: "Piece, color, or bin")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isSorting = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isSorting) {
                BulkSortSessionView()
            }
            .sheet(isPresented: $isPasting) {
                BulkPasteImportView()
            }
            .sheet(isPresented: $showBinMap) {
                StorageMapView()
            }
        }
    }
}

private struct BulkPieceRow: View {
    let piece: BulkPieceRecord

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.teal.opacity(0.15))
                .frame(width: 46, height: 46)
                .overlay {
                    Text("\(piece.quantity)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.teal)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(piece.name)
                    .font(.headline)
                Text("#\(piece.partNumber) · \(piece.color)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(piece.binCode)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppTheme.yellow.opacity(0.25), in: Capsule())
        }
        .padding(.vertical, 3)
    }
}
