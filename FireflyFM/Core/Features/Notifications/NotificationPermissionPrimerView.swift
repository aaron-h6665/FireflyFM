import SwiftUI

struct NotificationPermissionPrimerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var onFinished: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(AppConstants.Colors.primaryAction)
                    .frame(width: 104, height: 104)
                    .background(AppConstants.Colors.wingMist)
                    .clipShape(Circle())

                VStack(spacing: 10) {
                    Text("Stay connected to your school")
                        .font(.title.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .multilineTextAlignment(.center)
                    Text("Get alerts for messages, assignments, school updates, and time-sensitive care needs. Message text stays hidden on the lock screen unless you choose to show it.")
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    primerRow("Messages and replies", symbol: "message.fill")
                    primerRow("School posts, newsletters, and albums", symbol: "photo.on.rectangle.angled")
                    primerRow("Important care and workflow alerts", symbol: "checkmark.shield.fill")
                }
                .padding()
                .background(AppConstants.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))

                Spacer()
                Button { enableNotifications() } label: {
                    HStack {
                        if isRequesting { ProgressView().tint(.white) }
                        Text(isRequesting ? "Enabling…" : "Enable Notifications")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: AppConstants.Layout.minimumTapTarget)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)

                Button("Not Now") {
                    Task {
                        await PushNotificationManager.shared.deferPermissionPrimer()
                        onFinished()
                        dismiss()
                    }
                }
                .font(.subheadline.bold())
                .disabled(isRequesting)
            }
            .padding(24)
            .background(AppConstants.Colors.background.ignoresSafeArea())
        }
        .interactiveDismissDisabled()
    }

    private func primerRow(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppConstants.Colors.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func enableNotifications() {
        isRequesting = true
        Task {
            _ = await PushNotificationManager.shared.requestAuthorization()
            await PushNotificationManager.shared.registerIfAuthorized()
            isRequesting = false
            onFinished()
            dismiss()
        }
    }
}
