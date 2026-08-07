import Foundation
import SwiftData

nonisolated enum BoxCondition: String, CaseIterable, Identifiable, Codable {
    case sealed = "Sealed"
    case opened = "Opened"
    case incomplete = "Incomplete"

    var id: String { rawValue }
}

nonisolated enum BoxStatus: String, CaseIterable, Identifiable, Codable {
    case stored = "Stored"
    case sorting = "Sorting"
    case building = "Building"
    case displayed = "Displayed"

    var id: String { rawValue }
}

nonisolated enum PlanSource: String, CaseIterable, Identifiable, Codable {
    case official = "Official"
    case community = "Community"
    case custom = "Custom"

    var id: String { rawValue }
}

@Model
final class SetBox {
    @Attribute(.unique) var id: UUID
    var setNumber: String
    var label: String
    var storageLocation: String
    var conditionRaw: String
    var statusRaw: String
    var purchasePriceCents: Int
    var purchaseDate: Date?
    var seller: String
    var notes: String
    @Attribute(.externalStorage) var photoData: Data?
    @Attribute(.externalStorage) var receiptData: Data?
    var createdAt: Date
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        setNumber: String,
        label: String,
        storageLocation: String = "",
        condition: BoxCondition = .opened,
        status: BoxStatus = .stored,
        purchasePriceCents: Int = 0,
        purchaseDate: Date? = nil,
        seller: String = "",
        notes: String = "",
        photoData: Data? = nil,
        receiptData: Data? = nil,
        createdAt: Date = .now,
        isArchived: Bool = false
    ) {
        self.id = id
        self.setNumber = setNumber
        self.label = label
        self.storageLocation = storageLocation
        self.conditionRaw = condition.rawValue
        self.statusRaw = status.rawValue
        self.purchasePriceCents = purchasePriceCents
        self.purchaseDate = purchaseDate
        self.seller = seller
        self.notes = notes
        self.photoData = photoData
        self.receiptData = receiptData
        self.createdAt = createdAt
        self.isArchived = isArchived
    }

    var condition: BoxCondition {
        get { BoxCondition(rawValue: conditionRaw) ?? .opened }
        set { conditionRaw = newValue.rawValue }
    }

    var status: BoxStatus {
        get { BoxStatus(rawValue: statusRaw) ?? .stored }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class MissingPieceRecord {
    @Attribute(.unique) var id: UUID
    var boxID: UUID
    var partNumber: String
    var name: String
    var color: String
    var quantity: Int
    var notes: String
    var createdAt: Date
    var resolvedAt: Date?

    init(
        id: UUID = UUID(),
        boxID: UUID,
        partNumber: String,
        name: String,
        color: String,
        quantity: Int,
        notes: String = "",
        createdAt: Date = .now,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.boxID = boxID
        self.partNumber = partNumber
        self.name = name
        self.color = color
        self.quantity = max(1, quantity)
        self.notes = notes
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }

    var isResolved: Bool { resolvedAt != nil }
}

@Model
final class BulkPieceRecord {
    @Attribute(.unique) var id: UUID
    var partNumber: String
    var name: String
    var color: String
    var quantity: Int
    var binCode: String
    var notes: String
    @Attribute(.externalStorage) var photoData: Data?
    var updatedAt: Date
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        partNumber: String,
        name: String,
        color: String,
        quantity: Int,
        binCode: String,
        notes: String = "",
        photoData: Data? = nil,
        updatedAt: Date = .now,
        isArchived: Bool = false
    ) {
        self.id = id
        self.partNumber = partNumber
        self.name = name
        self.color = color
        self.quantity = max(0, quantity)
        self.binCode = binCode
        self.notes = notes
        self.photoData = photoData
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }
}

@Model
final class StorageBin {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var code: String
    var name: String
    var zone: String
    var sortRule: String
    var colorHex: String
    var createdAt: Date
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        code: String,
        name: String,
        zone: String,
        sortRule: String,
        colorHex: String,
        createdAt: Date = .now,
        isArchived: Bool = false
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.zone = zone
        self.sortRule = sortRule
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.isArchived = isArchived
    }
}

nonisolated struct PartRequirement: Codable, Hashable, Identifiable {
    var id: String { "\(partNumber)-\(color)" }
    let partNumber: String
    let name: String
    let color: String
    let quantity: Int
}

@Model
final class BuildPlanRecord {
    @Attribute(.unique) var id: UUID
    var setNumber: String
    var name: String
    var sourceRaw: String
    var creator: String
    var instructionsURLString: String
    var requirementsData: Data
    var isCompleteInventory: Bool
    var createdAt: Date
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        setNumber: String,
        name: String,
        source: PlanSource,
        creator: String,
        instructionsURLString: String,
        requirements: [PartRequirement],
        isCompleteInventory: Bool,
        createdAt: Date = .now,
        isArchived: Bool = false
    ) {
        self.id = id
        self.setNumber = setNumber
        self.name = name
        self.sourceRaw = source.rawValue
        self.creator = creator
        self.instructionsURLString = instructionsURLString
        self.requirementsData = (try? JSONEncoder().encode(requirements)) ?? Data()
        self.isCompleteInventory = isCompleteInventory
        self.createdAt = createdAt
        self.isArchived = isArchived
    }

    var source: PlanSource {
        get { PlanSource(rawValue: sourceRaw) ?? .custom }
        set { sourceRaw = newValue.rawValue }
    }

    var requirements: [PartRequirement] {
        get { (try? JSONDecoder().decode([PartRequirement].self, from: requirementsData)) ?? [] }
        set { requirementsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var instructionsURL: URL? { URL(string: instructionsURLString) }
}

@Model
final class InventoryEvent {
    @Attribute(.unique) var id: UUID
    var kind: String
    var title: String
    var detail: String
    var createdAt: Date

    init(id: UUID = UUID(), kind: String, title: String, detail: String, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
    }
}
