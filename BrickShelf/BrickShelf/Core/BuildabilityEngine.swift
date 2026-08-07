import Foundation

struct BuildRequirementStatus: Identifiable {
    var id: String { requirement.id }
    let requirement: PartRequirement
    let available: Int

    var missing: Int { max(0, requirement.quantity - available) }
    var isSatisfied: Bool { missing == 0 }
}

struct BuildReadiness {
    let statuses: [BuildRequirementStatus]

    var requiredCount: Int { statuses.reduce(0) { $0 + $1.requirement.quantity } }
    var availableCount: Int { statuses.reduce(0) { $0 + min($1.available, $1.requirement.quantity) } }
    var missingCount: Int { statuses.reduce(0) { $0 + $1.missing } }
    var progress: Double { requiredCount == 0 ? 0 : Double(availableCount) / Double(requiredCount) }
    var isBuildable: Bool { !statuses.isEmpty && missingCount == 0 }
}

enum BuildabilityEngine {
    static func readiness(for plan: BuildPlanRecord, bulk: [BulkPieceRecord]) -> BuildReadiness {
        let activeBulk = bulk.filter { !$0.isArchived && $0.quantity > 0 }
        let statuses = plan.requirements.map { requirement in
            let available = activeBulk
                .filter {
                    $0.partNumber.caseInsensitiveCompare(requirement.partNumber) == .orderedSame
                        && $0.color.caseInsensitiveCompare(requirement.color) == .orderedSame
                }
                .reduce(0) { $0 + $1.quantity }
            return BuildRequirementStatus(requirement: requirement, available: available)
        }
        return BuildReadiness(statuses: statuses)
    }
}
