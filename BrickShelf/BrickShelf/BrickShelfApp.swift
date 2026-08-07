import SwiftData
import SwiftUI

@main
struct BrickShelfApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([
            SetBox.self,
            MissingPieceRecord.self,
            BulkPieceRecord.self,
            StorageBin.self,
            BuildPlanRecord.self,
            InventoryEvent.self
        ])

        do {
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration("BrickShelf", schema: schema)]
            )
        } catch {
            fatalError("Unable to open the collection database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    SeedService.seedIfNeeded(in: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
