import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let brickShelfBackup = UTType(exportedAs: "com.example.brickshelf.backup", conformingTo: .json)
}

nonisolated struct BackupSnapshot: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let boxes: [BoxDTO]
    let missingPieces: [MissingDTO]
    let bulkPieces: [BulkDTO]
    let bins: [BinDTO]
    let plans: [PlanDTO]
    let events: [EventDTO]

    static let empty = BackupSnapshot(
        schemaVersion: 1,
        exportedAt: .now,
        boxes: [],
        missingPieces: [],
        bulkPieces: [],
        bins: [],
        plans: [],
        events: []
    )

    @MainActor
    static func make(from context: ModelContext) throws -> BackupSnapshot {
        BackupSnapshot(
            schemaVersion: 1,
            exportedAt: .now,
            boxes: try context.fetch(FetchDescriptor<SetBox>()).map(BoxDTO.init),
            missingPieces: try context.fetch(FetchDescriptor<MissingPieceRecord>()).map(MissingDTO.init),
            bulkPieces: try context.fetch(FetchDescriptor<BulkPieceRecord>()).map(BulkDTO.init),
            bins: try context.fetch(FetchDescriptor<StorageBin>()).map(BinDTO.init),
            plans: try context.fetch(FetchDescriptor<BuildPlanRecord>()).map(PlanDTO.init),
            events: try context.fetch(FetchDescriptor<InventoryEvent>()).map(EventDTO.init)
        )
    }

    @MainActor
    func merge(into context: ModelContext) throws -> Int {
        guard schemaVersion == 1 else {
            throw BackupError.unsupportedVersion(schemaVersion)
        }

        var inserted = 0

        let existingBoxIDs = Set(try context.fetch(FetchDescriptor<SetBox>()).map(\.id))
        for item in boxes where !existingBoxIDs.contains(item.id) {
            context.insert(item.model)
            inserted += 1
        }

        let existingMissingIDs = Set(try context.fetch(FetchDescriptor<MissingPieceRecord>()).map(\.id))
        for item in missingPieces where !existingMissingIDs.contains(item.id) {
            context.insert(item.model)
            inserted += 1
        }

        let existingBulkIDs = Set(try context.fetch(FetchDescriptor<BulkPieceRecord>()).map(\.id))
        for item in bulkPieces where !existingBulkIDs.contains(item.id) {
            context.insert(item.model)
            inserted += 1
        }

        let existingBins = try context.fetch(FetchDescriptor<StorageBin>())
        let existingBinIDs = Set(existingBins.map(\.id))
        let existingBinCodes = Set(existingBins.map(\.code))
        for item in bins where !existingBinIDs.contains(item.id) && !existingBinCodes.contains(item.code) {
            context.insert(item.model)
            inserted += 1
        }

        let existingPlanIDs = Set(try context.fetch(FetchDescriptor<BuildPlanRecord>()).map(\.id))
        for item in plans where !existingPlanIDs.contains(item.id) {
            context.insert(item.model)
            inserted += 1
        }

        let existingEventIDs = Set(try context.fetch(FetchDescriptor<InventoryEvent>()).map(\.id))
        for item in events where !existingEventIDs.contains(item.id) {
            context.insert(item.model)
            inserted += 1
        }

        context.insert(InventoryEvent(kind: "backup", title: "Backup restored", detail: "Merged \(inserted) records without deleting current data"))
        try context.save()
        return inserted
    }
}

nonisolated enum BackupError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This backup uses unsupported schema version \(version)."
        }
    }
}

nonisolated struct BoxDTO: Codable {
    let id: UUID
    let setNumber: String
    let label: String
    let storageLocation: String
    let conditionRaw: String
    let statusRaw: String
    let purchasePriceCents: Int
    let purchaseDate: Date?
    let seller: String
    let notes: String
    let photoData: Data?
    let receiptData: Data?
    let createdAt: Date
    let isArchived: Bool

    init(_ model: SetBox) {
        id = model.id
        setNumber = model.setNumber
        label = model.label
        storageLocation = model.storageLocation
        conditionRaw = model.conditionRaw
        statusRaw = model.statusRaw
        purchasePriceCents = model.purchasePriceCents
        purchaseDate = model.purchaseDate
        seller = model.seller
        notes = model.notes
        photoData = model.photoData
        receiptData = model.receiptData
        createdAt = model.createdAt
        isArchived = model.isArchived
    }

    var model: SetBox {
        SetBox(
            id: id,
            setNumber: setNumber,
            label: label,
            storageLocation: storageLocation,
            condition: BoxCondition(rawValue: conditionRaw) ?? .opened,
            status: BoxStatus(rawValue: statusRaw) ?? .stored,
            purchasePriceCents: purchasePriceCents,
            purchaseDate: purchaseDate,
            seller: seller,
            notes: notes,
            photoData: photoData,
            receiptData: receiptData,
            createdAt: createdAt,
            isArchived: isArchived
        )
    }
}

nonisolated struct MissingDTO: Codable {
    let id: UUID
    let boxID: UUID
    let partNumber: String
    let name: String
    let color: String
    let quantity: Int
    let notes: String
    let createdAt: Date
    let resolvedAt: Date?

    init(_ model: MissingPieceRecord) {
        id = model.id
        boxID = model.boxID
        partNumber = model.partNumber
        name = model.name
        color = model.color
        quantity = model.quantity
        notes = model.notes
        createdAt = model.createdAt
        resolvedAt = model.resolvedAt
    }

    var model: MissingPieceRecord {
        MissingPieceRecord(id: id, boxID: boxID, partNumber: partNumber, name: name, color: color, quantity: quantity, notes: notes, createdAt: createdAt, resolvedAt: resolvedAt)
    }
}

nonisolated struct BulkDTO: Codable {
    let id: UUID
    let partNumber: String
    let name: String
    let color: String
    let quantity: Int
    let binCode: String
    let notes: String
    let photoData: Data?
    let updatedAt: Date
    let isArchived: Bool

    init(_ model: BulkPieceRecord) {
        id = model.id
        partNumber = model.partNumber
        name = model.name
        color = model.color
        quantity = model.quantity
        binCode = model.binCode
        notes = model.notes
        photoData = model.photoData
        updatedAt = model.updatedAt
        isArchived = model.isArchived
    }

    var model: BulkPieceRecord {
        BulkPieceRecord(id: id, partNumber: partNumber, name: name, color: color, quantity: quantity, binCode: binCode, notes: notes, photoData: photoData, updatedAt: updatedAt, isArchived: isArchived)
    }
}

nonisolated struct BinDTO: Codable {
    let id: UUID
    let code: String
    let name: String
    let zone: String
    let sortRule: String
    let colorHex: String
    let createdAt: Date
    let isArchived: Bool

    init(_ model: StorageBin) {
        id = model.id
        code = model.code
        name = model.name
        zone = model.zone
        sortRule = model.sortRule
        colorHex = model.colorHex
        createdAt = model.createdAt
        isArchived = model.isArchived
    }

    var model: StorageBin {
        StorageBin(id: id, code: code, name: name, zone: zone, sortRule: sortRule, colorHex: colorHex, createdAt: createdAt, isArchived: isArchived)
    }
}

nonisolated struct PlanDTO: Codable {
    let id: UUID
    let setNumber: String
    let name: String
    let sourceRaw: String
    let creator: String
    let instructionsURLString: String
    let requirements: [PartRequirement]
    let isCompleteInventory: Bool
    let createdAt: Date
    let isArchived: Bool

    init(_ model: BuildPlanRecord) {
        id = model.id
        setNumber = model.setNumber
        name = model.name
        sourceRaw = model.sourceRaw
        creator = model.creator
        instructionsURLString = model.instructionsURLString
        requirements = model.requirements
        isCompleteInventory = model.isCompleteInventory
        createdAt = model.createdAt
        isArchived = model.isArchived
    }

    var model: BuildPlanRecord {
        BuildPlanRecord(
            id: id,
            setNumber: setNumber,
            name: name,
            source: PlanSource(rawValue: sourceRaw) ?? .custom,
            creator: creator,
            instructionsURLString: instructionsURLString,
            requirements: requirements,
            isCompleteInventory: isCompleteInventory,
            createdAt: createdAt,
            isArchived: isArchived
        )
    }
}

nonisolated struct EventDTO: Codable {
    let id: UUID
    let kind: String
    let title: String
    let detail: String
    let createdAt: Date

    init(_ model: InventoryEvent) {
        id = model.id
        kind = model.kind
        title = model.title
        detail = model.detail
        createdAt = model.createdAt
    }

    var model: InventoryEvent {
        InventoryEvent(id: id, kind: kind, title: title, detail: detail, createdAt: createdAt)
    }
}

nonisolated struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.brickShelfBackup, .json] }

    var snapshot: BackupSnapshot

    init(snapshot: BackupSnapshot) {
        self.snapshot = snapshot
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshot = try decoder.decode(BackupSnapshot.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(snapshot))
    }
}
