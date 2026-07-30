import SDWebImageSwiftUI
import SwiftUI

enum ChatRoomAction: String, Identifiable {
    case everydayCare
    case familyRequest
    case callGuardians

    var id: String { rawValue }
}

struct ChatRoomScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var room: ChatRoom
    @State private var infoModel = ChatRoomInfoModel()
    @State private var searchTrigger = 0
    @State private var showingSettings = false
    @State private var activeAction: ChatRoomAction?

    var onRoomChanged: () -> Void

    private var accessPolicy: ChatAccessPolicy {
        ChatAccessPolicy(context: appSession.accessContext(selectedSchoolId: room.schoolId))
    }

    private var roomCapabilities: ChatRoomCapabilities {
        ChatRoomInteractionPolicy(
            context: appSession.accessContext(selectedSchoolId: room.schoolId),
            room: room
        ).capabilities
    }
    private var memberCount: Int { infoModel.memberCount }

    init(room: ChatRoom, onRoomChanged: @escaping () -> Void = {}) {
        _room = State(initialValue: room)
        self.onRoomChanged = onRoomChanged
    }

    var body: some View {
        ChatViewWrapper(
            room: room,
            capabilities: roomCapabilities,
            searchTrigger: searchTrigger,
            onAction: { activeAction = $0 }
        )
            .toolbar(.hidden, for: .tabBar)
            .toolbarBackground(AppConstants.Colors.card, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        showingSettings = true
                    } label: {
                        HStack(spacing: 12) {
                            roomAvatar(size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(room.name).font(.headline).lineLimit(1)
                                Text("\(memberCount) members").font(.caption2).foregroundColor(AppConstants.Colors.secondaryText)
                            }
                            .foregroundColor(AppConstants.Colors.primaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View \(room.name) details and members")
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        searchTrigger += 1
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(AppConstants.Colors.primaryText)

                    if accessPolicy.canOverseeSchoolRooms {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(AppConstants.Colors.primaryText)
                    } else {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(AppConstants.Colors.primaryText)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                ChatRoomSettingsView(
                    room: room,
                    onRoomUpdated: { updatedRoom in
                        room = updatedRoom
                        onRoomChanged()
                    },
                    onRoomClosed: {
                        showingSettings = false
                        onRoomChanged()
                        dismiss()
                    }
                )
            }
            .sheet(item: $activeAction) { action in
                switch action {
                case .everydayCare:
                    if let childId = room.subjectChildId {
                        ChatDailyActivityComposerView(childId: childId, roomId: room.id)
                    } else {
                        ContentUnavailableView("No linked child", systemImage: "heart.slash.fill")
                    }
                case .familyRequest:
                    if let childId = room.subjectChildId {
                        ChatFamilyRequestComposerView(childId: childId)
                    } else {
                        ContentUnavailableView("No linked child", systemImage: "person.crop.circle.badge.exclamationmark")
                    }
                case .callGuardians:
                    if let childId = room.subjectChildId {
                        CallGuardiansView(childId: childId)
                    } else {
                        ContentUnavailableView("No linked child", systemImage: "phone.down.fill")
                    }
                }
            }
            .task {
                PushNotificationManager.shared.setVisibleChatRoom(room.id)
                try? await SchoolWorkflowService.shared.markNotificationThreadRead(threadKey: "chat:\(room.id.uuidString)")
                await infoModel.load(roomId: room.id)
            }
            .onDisappear {
                PushNotificationManager.shared.setVisibleChatRoom(nil)
            }
    }

    @ViewBuilder
    private func roomAvatar(size: CGFloat) -> some View {
        if let profileUrl = room.profileImageUrl, let url = URL(string: profileUrl) {
            WebImage(url: url)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(room.name.prefix(1)).uppercased())
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                )
        }
    }
}
