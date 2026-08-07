import SwiftData
import SwiftUI

struct BuildPlansView: View {
    @Query(sort: \BuildPlanRecord.createdAt) private var plans: [BuildPlanRecord]
    @Query private var bulk: [BulkPieceRecord]
    @State private var isAddingPlan = false

    private var activePlans: [BuildPlanRecord] { plans.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("What can I build?", systemImage: "hammer.fill")
                            .font(.title2.bold())
                        Text("BrickShelf compares requirements with every matching part across your labeled bins, then shows exactly what is still missing and where available pieces live.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Plans") {
                    ForEach(activePlans) { plan in
                        NavigationLink {
                            BuildPlanDetailView(plan: plan)
                        } label: {
                            BuildPlanRow(plan: plan, readiness: BuildabilityEngine.readiness(for: plan, bulk: bulk))
                        }
                    }
                }

                Section {
                    Button {
                        isAddingPlan = true
                    } label: {
                        Label("Add custom or community plan", systemImage: "plus.circle.fill")
                    }
                } footer: {
                    Text("Community instructions stay linked to their creator. Import only inventories and instructions you are permitted to use.")
                }
            }
            .navigationTitle("Build Finder")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isAddingPlan = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isAddingPlan) {
                AddBuildPlanView()
            }
        }
    }
}

private struct BuildPlanRow: View {
    let plan: BuildPlanRecord
    let readiness: BuildReadiness

    var body: some View {
        let isVerifiedBuildable = plan.isCompleteInventory && readiness.isBuildable
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: readiness.progress)
                    .stroke(isVerifiedBuildable ? AppTheme.teal : AppTheme.yellow, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(readiness.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.bold())
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name).font(.headline)
                Text("\(plan.source.rawValue) · \(plan.creator)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isVerifiedBuildable ? AppTheme.teal : AppTheme.coral)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        if !plan.isCompleteInventory {
            return readiness.missingCount == 0 ? "Tracked sample satisfied" : "Sample needs \(readiness.missingCount) more"
        }
        return readiness.isBuildable ? "Ready from bulk" : "\(readiness.missingCount) pieces still needed"
    }
}
