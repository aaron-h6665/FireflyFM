import Foundation
import Observation

struct AppShellClient {
    var prepareNotifications: () async -> Void

    static let live = AppShellClient(
        prepareNotifications: {
            await ChatNotificationManager.shared.requestAuthorization()
            await ChatNotificationManager.shared.syncPendingDeviceToken()
        }
    )
}

@MainActor
@Observable
final class AppShellModel {
    private let client: AppShellClient

    init() { client = .live }
    init(client: AppShellClient) { self.client = client }

    func prepareNotifications() async {
        await client.prepareNotifications()
    }
}
