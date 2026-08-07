import SwiftUI

struct RootView: View {
    private enum AppTab: String {
        case overview, sets, bulk, build
    }

    @State private var selectedTab: AppTab

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let requestedTab: AppTab
        if let index = arguments.firstIndex(of: "--tab"), arguments.indices.contains(index + 1) {
            requestedTab = AppTab(rawValue: arguments[index + 1]) ?? .overview
        } else {
            requestedTab = .overview
        }
        _selectedTab = State(initialValue: requestedTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView()
                .tabItem { Label("Overview", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.overview)

            CollectionView()
                .tabItem { Label("Sets", systemImage: "shippingbox.fill") }
                .tag(AppTab.sets)

            BulkInventoryView()
                .tabItem { Label("Bulk", systemImage: "square.3.layers.3d") }
                .tag(AppTab.bulk)

            BuildPlansView()
                .tabItem { Label("Build", systemImage: "hammer.fill") }
                .tag(AppTab.build)
        }
        .tint(AppTheme.blue)
    }
}
