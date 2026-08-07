import Foundation
import SwiftData

@MainActor
enum SeedService {
    static func seedIfNeeded(in context: ModelContext) {
        let existingBins = (try? context.fetchCount(FetchDescriptor<StorageBin>())) ?? 0
        guard existingBins == 0 else { return }

        let bins = [
            StorageBin(code: "A1", name: "Plates", zone: "Wall rack", sortRule: "Plates and tiles", colorHex: "2A9D8F"),
            StorageBin(code: "A2", name: "Bricks", zone: "Wall rack", sortRule: "Standard bricks", colorHex: "E9C46A"),
            StorageBin(code: "B1", name: "Technic", zone: "Drawer unit", sortRule: "Pins, axles and connectors", colorHex: "E76F51"),
            StorageBin(code: "C1", name: "Special", zone: "Small parts case", sortRule: "Rare and printed pieces", colorHex: "457B9D")
        ]
        bins.forEach(context.insert)

        let bulk = [
            BulkPieceRecord(partNumber: "3001", name: "Brick 2 x 4", color: "Red", quantity: 18, binCode: "A2"),
            BulkPieceRecord(partNumber: "3001", name: "Brick 2 x 4", color: "Blue", quantity: 12, binCode: "A2"),
            BulkPieceRecord(partNumber: "3020", name: "Plate 2 x 4", color: "Light Gray", quantity: 24, binCode: "A1"),
            BulkPieceRecord(partNumber: "3069", name: "Tile 1 x 2", color: "White", quantity: 16, binCode: "A1"),
            BulkPieceRecord(partNumber: "2780", name: "Technic Pin", color: "Black", quantity: 30, binCode: "B1")
        ]
        bulk.forEach(context.insert)

        let officialRequirements = [
            PartRequirement(partNumber: "3001", name: "Brick 2 x 4", color: "Red", quantity: 20),
            PartRequirement(partNumber: "3020", name: "Plate 2 x 4", color: "Light Gray", quantity: 20),
            PartRequirement(partNumber: "3069", name: "Tile 1 x 2", color: "White", quantity: 12),
            PartRequirement(partNumber: "2780", name: "Technic Pin", color: "Black", quantity: 24)
        ]
        context.insert(BuildPlanRecord(
            setNumber: "31147",
            name: "Retro Camera — tracked sample",
            source: .official,
            creator: "LEGO.com instructions",
            instructionsURLString: "https://www.lego.com/en-us/service/buildinginstructions/31147",
            requirements: officialRequirements,
            isCompleteInventory: false
        ))

        let customRequirements = [
            PartRequirement(partNumber: "3001", name: "Brick 2 x 4", color: "Blue", quantity: 10),
            PartRequirement(partNumber: "3020", name: "Plate 2 x 4", color: "Light Gray", quantity: 8),
            PartRequirement(partNumber: "3069", name: "Tile 1 x 2", color: "White", quantity: 6)
        ]
        context.insert(BuildPlanRecord(
            setNumber: "CUSTOM-001",
            name: "Desktop Parts Tray",
            source: .custom,
            creator: "BrickShelf starter plan",
            instructionsURLString: "",
            requirements: customRequirements,
            isCompleteInventory: true
        ))

        context.insert(InventoryEvent(kind: "setup", title: "Storage map created", detail: "4 labeled bins are ready for sorting"))
        try? context.save()
    }
}
