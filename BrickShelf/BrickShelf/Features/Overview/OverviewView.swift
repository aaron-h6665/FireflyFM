import SwiftData
import SwiftUI

struct OverviewView: View {
    @Query private var boxes: [SetBox]
    @Query private var missingPieces: [MissingPieceRecord]
    @Query private var bulk: [BulkPieceRecord]
    @Query private var plans: [BuildPlanRecord]
    @Query(sort: \InventoryEvent.createdAt, order: .reverse) private var events: [InventoryEvent]
    @State private var isAddingSet = false
    @State private var isSortingBulk = false
    @State private var showSettings = false

    private var activeBoxes: [SetBox] { boxes.filter { !$0.isArchived } }
    private var activeBulk: [BulkPieceRecord] { bulk.filter { !$0.isArchived && $0.quantity > 0 } }
    private var openMissing: [MissingPieceRecord] { missingPieces.filter { !$0.isResolved } }
    private var activePlans: [BuildPlanRecord] { plans.filter { !$0.isArchived } }
    private var buildableCount: Int {
        activePlans.filter { $0.isCompleteInventory && BuildabilityEngine.readiness(for: $0, bulk: bulk).isBuildable }.count
    }
    private var collectionValue: Int { activeBoxes.reduce(0) { $0 + $1.purchasePriceCents } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your collection, findable.")
                            .font(.largeTitle.bold())
                        Text("Know what you own, where it lives, and what it can build.")
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricTile(
                            title: "Sets",
                            value: Set(activeBoxes.map(\.setNumber)).count.formatted(),
                            detail: "\(activeBoxes.count) physical boxes",
                            systemImage: "shippingbox.fill",
                            tint: AppTheme.blue
                        )
                        MetricTile(
                            title: "Missing",
                            value: openMissing.reduce(0) { $0 + $1.quantity }.formatted(),
                            detail: "across \(Set(openMissing.map(\.boxID)).count) boxes",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: AppTheme.coral
                        )
                        MetricTile(
                            title: "Bulk",
                            value: activeBulk.reduce(0) { $0 + $1.quantity }.formatted(),
                            detail: "\(activeBulk.count) piece groups",
                            systemImage: "square.3.layers.3d",
                            tint: AppTheme.teal
                        )
                        MetricTile(
                            title: "Ready to build",
                            value: buildableCount.formatted(),
                            detail: "of \(activePlans.count) plans",
                            systemImage: "hammer.fill",
                            tint: AppTheme.yellow
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick actions").font(.headline)
                        Button {
                            isAddingSet = true
                        } label: {
                            Label("Scan or add a set", systemImage: "barcode.viewfinder")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            isSortingBulk = true
                        } label: {
                            Label("Start a bulk sorting session", systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Collection value").font(.headline)
                            Spacer()
                            Text(currency(cents: collectionValue)).font(.headline.monospacedDigit())
                        }
                        Text("Based only on purchase prices you entered for each physical box. No market-value estimate is implied.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .appCard()

                    if !events.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent activity").font(.headline)
                            ForEach(events.prefix(5)) { event in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: icon(for: event.kind))
                                        .foregroundStyle(AppTheme.blue)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title).font(.subheadline.weight(.semibold))
                                        Text(event.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(event.createdAt, format: .relative(presentation: .named))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .appCard()
                    }
                }
                .padding()
            }
            .background(AppTheme.canvas)
            .navigationTitle("BrickShelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .sheet(isPresented: $isAddingSet) { AddSetFlow() }
            .sheet(isPresented: $isSortingBulk) { BulkSortSessionView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func currency(cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "box": return "shippingbox.fill"
        case "bulk", "quantity": return "square.3.layers.3d"
        case "missing": return "exclamationmark.circle.fill"
        case "archive": return "archivebox.fill"
        case "plan": return "hammer.fill"
        default: return "checkmark.circle.fill"
        }
    }
}
