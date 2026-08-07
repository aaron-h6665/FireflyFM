import SwiftData
import SwiftUI

struct BuildPlanDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bulk: [BulkPieceRecord]
    @Bindable var plan: BuildPlanRecord
    @State private var archiveConfirmation = false

    private var readiness: BuildReadiness { BuildabilityEngine.readiness(for: plan, bulk: bulk) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name).font(.title2.bold())
                            Text(plan.setNumber).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(readiness.progress, format: .percent.precision(.fractionLength(0)))
                            .font(.title.bold())
                            .foregroundStyle(readiness.isBuildable ? AppTheme.teal : AppTheme.yellow)
                    }

                    ProgressView(value: readiness.progress)
                        .tint(readiness.isBuildable ? AppTheme.teal : AppTheme.yellow)
                    Text(readiness.isBuildable ? "All tracked requirements are on hand." : "Find \(readiness.missingCount) more pieces to complete this plan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !plan.isCompleteInventory {
                        Label("Sample requirements only — not a complete official inventory", systemImage: "info.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.coral)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Requirements") {
                ForEach(readiness.statuses) { status in
                    RequirementRow(status: status, locations: locations(for: status.requirement))
                }
            }

            if let url = plan.instructionsURL, !plan.instructionsURLString.isEmpty {
                Section("Instructions") {
                    Link(destination: url) {
                        Label(plan.source == .official ? "Open on LEGO.com" : "Open creator instructions", systemImage: "safari.fill")
                    }
                    LabeledContent("Source", value: plan.creator)
                }
            }

            Section {
                Button("Archive build plan", role: .destructive) {
                    archiveConfirmation = true
                }
            } footer: {
                Text("Archiving removes the plan from Build Finder without changing any bulk quantities.")
            }
        }
        .navigationTitle("Build Plan")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Archive this plan?", isPresented: $archiveConfirmation) {
            Button("Archive", role: .destructive) {
                plan.isArchived = true
                modelContext.insert(InventoryEvent(kind: "archive", title: "Archived build plan", detail: plan.name))
                try? modelContext.save()
            }
        }
    }

    private func locations(for requirement: PartRequirement) -> String {
        let matches = bulk.filter {
            !$0.isArchived
                && $0.quantity > 0
                && $0.partNumber.caseInsensitiveCompare(requirement.partNumber) == .orderedSame
                && $0.color.caseInsensitiveCompare(requirement.color) == .orderedSame
        }
        let codes = Array(Set(matches.map(\.binCode))).sorted()
        return codes.isEmpty ? "Not in bulk" : codes.joined(separator: ", ")
    }
}

private struct RequirementRow: View {
    let status: BuildRequirementStatus
    let locations: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.isSatisfied ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(status.isSatisfied ? AppTheme.teal : AppTheme.coral)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.requirement.name).font(.headline)
                Text("#\(status.requirement.partNumber) · \(status.requirement.color) · \(locations)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(min(status.available, status.requirement.quantity))/\(status.requirement.quantity)")
                    .font(.headline.monospacedDigit())
                if status.missing > 0 {
                    Text("need \(status.missing)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.coral)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
