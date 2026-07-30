//
//  ProfileView.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/10/26.
//

import SwiftUI
import PhotosUI
import SDWebImageSwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss

    let profileUserId: UUID?

    @State private var model = ProfileModel()
    @State private var displayName = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedAvatarData: Data?

    init(profileUserId: UUID? = nil) {
        self.profileUserId = profileUserId
    }

    private var canEdit: Bool {
        profileUserId == nil || profileUserId == model.currentUserId
    }
    private var profile: UserProfile? { model.profile }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                if model.phase.isLoading {
                    ProgressView()
                        .tint(AppConstants.Colors.accessibleYellow)
                } else {
                    ScrollView {
                        VStack(spacing: 22) {
                            avatarEditor

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Name")
                                    .font(.caption.bold())
                                    .foregroundColor(AppConstants.Colors.accessibleYellow)

                                if canEdit {
                                    TextField("Display name", text: $displayName)
                                        .textInputAutocapitalization(.words)
                                        .padding(12)
                                        .background(AppConstants.Colors.card)
                                        .cornerRadius(8)
                                        .foregroundColor(AppConstants.Colors.primaryText)
                                        .tint(AppConstants.Colors.accessibleYellow)
                                } else {
                                    Text(displayName)
                                        .font(.title3.bold())
                                        .foregroundColor(AppConstants.Colors.primaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if canEdit {
                                Button {
                                    saveProfile()
                                } label: {
                                    Label(model.isSaving ? "Saving" : "Save Profile", systemImage: "checkmark.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(ProfilePrimaryButtonStyle())
                                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving)
                            }

                            if let errorMessage = model.errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(canEdit ? "Profile" : "Member Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                }
            }
            .task {
                await loadProfile()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task { await loadSelectedAvatar(from: newItem) }
            }
        }
    }

    @ViewBuilder
    private var avatarEditor: some View {
        VStack(spacing: 12) {
            avatarImage
                .frame(width: 112, height: 112)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppConstants.Colors.accessibleYellow.opacity(0.45), lineWidth: 2))

            if canEdit {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Change Photo", systemImage: "camera.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let selectedAvatarData, let image = UIImage(data: selectedAvatarData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let avatarUrl = profile?.avatarUrl, let url = URL(string: avatarUrl) {
            WebImage(url: url)
                .resizable()
                .scaledToFill()
        } else {
            Circle()
                .fill(AppConstants.Colors.card)
                .overlay(
                    Text(profile?.initials ?? "?")
                        .font(.largeTitle.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                )
        }
    }

    @MainActor
    private func loadProfile() async {
        await model.load(profileUserId: profileUserId)
        displayName = model.profile?.displayName ?? ""
    }

    @MainActor
    private func loadSelectedAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            selectedAvatarData = try await item.loadTransferable(type: Data.self)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            model.showPhotoError(error)
        }
    }

    private func saveProfile() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        Task {
            if await model.save(displayName: trimmedName, avatarData: selectedAvatarData) {
                displayName = model.profile?.displayName ?? trimmedName
                selectedAvatarData = nil
            }
        }
    }
}

struct ProfileAvatarView: View {
    let profile: UserProfile?
    let fallbackName: String
    let size: CGFloat

    init(profile: UserProfile?, fallbackName: String = "?", size: CGFloat = 40) {
        self.profile = profile
        self.fallbackName = fallbackName
        self.size = size
    }

    var body: some View {
        Group {
            if let avatarUrl = profile?.avatarUrl, let url = URL(string: avatarUrl) {
                WebImage(url: url)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(AppConstants.Colors.card)
                    .overlay(
                        Text(initials)
                            .font(.system(size: max(12, size * 0.34), weight: .bold))
                            .foregroundColor(AppConstants.Colors.primaryText)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        if let profile {
            return profile.initials
        }

        return InitialsFormatter.initials(for: fallbackName, fallback: "?")
    }
}

private struct ProfilePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(AppConstants.Colors.primaryActionText)
            .padding(.vertical, 12)
            .background(AppConstants.Colors.primaryAction.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
    }
}
