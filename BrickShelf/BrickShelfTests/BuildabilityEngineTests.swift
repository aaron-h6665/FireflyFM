import Testing
@testable import BrickShelf

@MainActor
struct BuildabilityEngineTests {
    @Test
    func aggregatesMatchingPiecesAcrossBins() {
        let plan = BuildPlanRecord(
            setNumber: "TEST",
            name: "Test plan",
            source: .custom,
            creator: "Tests",
            instructionsURLString: "",
            requirements: [PartRequirement(partNumber: "3001", name: "Brick 2 x 4", color: "Red", quantity: 5)],
            isCompleteInventory: true
        )
        let bulk = [
            BulkPieceRecord(partNumber: "3001", name: "Brick 2 x 4", color: "Red", quantity: 2, binCode: "A1"),
            BulkPieceRecord(partNumber: "3001", name: "Brick 2 x 4", color: "Red", quantity: 3, binCode: "B2")
        ]

        let readiness = BuildabilityEngine.readiness(for: plan, bulk: bulk)

        #expect(readiness.isBuildable)
        #expect(readiness.availableCount == 5)
        #expect(readiness.missingCount == 0)
    }

    @Test
    func excludesWrongColorsAndArchivedInventory() {
        let plan = BuildPlanRecord(
            setNumber: "TEST",
            name: "Test plan",
            source: .custom,
            creator: "Tests",
            instructionsURLString: "",
            requirements: [PartRequirement(partNumber: "3001", name: "Brick 2 x 4", color: "Red", quantity: 5)],
            isCompleteInventory: true
        )
        let bulk = [
            BulkPieceRecord(partNumber: "3001", name: "Brick 2 x 4", color: "Blue", quantity: 20, binCode: "A1"),
            BulkPieceRecord(partNumber: "3001", name: "Brick 2 x 4", color: "Red", quantity: 4, binCode: "A2", isArchived: true)
        ]

        let readiness = BuildabilityEngine.readiness(for: plan, bulk: bulk)

        #expect(!readiness.isBuildable)
        #expect(readiness.missingCount == 5)
    }

    @Test
    func extractsSupportedSetNumberFromInstructionURL() {
        let scanned = "https://www.lego.com/en-us/service/buildinginstructions/21338"
        #expect(SetCatalog.setNumber(fromScannedValue: scanned) == "21338")
    }
}
