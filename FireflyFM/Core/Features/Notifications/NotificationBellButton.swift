import SwiftUI

struct NotificationBellButton: View {
    @EnvironmentObject private var inbox: NotificationInboxStore
    @State private var showingInbox = false

    var body: some View {
        Button {
            showingInbox = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: inbox.unreadCount > 0 ? "bell.fill" : "bell")
                    .font(.system(size: 21, weight: .semibold))
                    .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)

                if inbox.unreadCount > 0 {
                    Text(inbox.unreadCount > 99 ? "99+" : "\(inbox.unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 4, y: 2)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(AppConstants.Colors.primaryAction)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(inbox.unreadCount == 0 ? "Notifications" : "Notifications, \(inbox.unreadCount) unread")
        .sheet(isPresented: $showingInbox) {
            NotificationsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
