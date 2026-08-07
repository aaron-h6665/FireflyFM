import SwiftData
import SwiftUI

struct StorageMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StorageBin.code) private var bins: [StorageBin]
    @Query private var bulk: [BulkPieceRecord]

    var body: some View {
        NavigationStack {
            List {
                ForEach(bins.filter { !$0.isArchived }) { bin in
                    HStack(spacing: 14) {
                        Text(bin.code)
                            .font(.headline.monospaced())
                            .frame(width: 48, height: 48)
                            .background(color(hex: bin.colorHex).opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(color(hex: bin.colorHex))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bin.name).font(.headline)
                            Text("\(bin.zone) · \(bin.sortRule)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            let records = bulk.filter { !$0.isArchived && $0.binCode == bin.code }
                            Text("\(records.reduce(0) { $0 + $1.quantity }.formatted()) pieces · \(records.count) groups")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Storage Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func color(hex: String) -> Color {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
