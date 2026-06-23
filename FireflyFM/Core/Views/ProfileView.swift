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

    @State private var currentUserId: UUID?
    @State private var profile: UserProfile?
    @State private var displayName = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedAvatarData: Data?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profileUserId: UUID? = nil) {
        self.profileUserId = profileUserId
    }

    private var canEdit: Bool {
        profileUserId == nil || profileUserId == currentUserId
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                if isLoading {
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
                                        .foregroundColor(.white)
                                        .tint(AppConstants.Colors.accessibleYellow)
                                } else {
                                    Text(displayName)
                                        .font(.title3.bold())
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if canEdit {
                                Button {
                                    saveProfile()
                                } label: {
                                    Label(isSaving ? "Saving" : "Save Profile", systemImage: "checkmark.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(ProfilePrimaryButtonStyle())
                                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                            }

                            if let errorMessage {
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
                        .foregroundColor(.white)
                )
        }
    }

    @MainActor
    private func loadProfile() async {
        isLoading = true
        errorMessage = nil

        do {
            let myUserId = try await ProfileService.shared.currentUserId()
            currentUserId = myUserId

            let targetUserId = profileUserId ?? myUserId
            let loadedProfile: UserProfile
            if targetUserId == myUserId {
                loadedProfile = try await ProfileService.shared.fetchCurrentProfile()
            } else if let fetchedProfile = try await ProfileService.shared.fetchProfile(id: targetUserId) {
                loadedProfile = fetchedProfile
            } else {
                loadedProfile = UserProfile(id: targetUserId, displayName: "Firefly User", avatarUrl: nil)
            }

            profile = loadedProfile
            displayName = loadedProfile.displayName
            isLoading = false
        } catch where AppErrorMessage.isCancellation(error) {
            isLoading = false
        } catch {
            errorMessage = AppErrorMessage.school("Could not load profile", error)
            isLoading = false
        }
    }

    @MainActor
    private func loadSelectedAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            selectedAvatarData = try await item.loadTransferable(type: Data.self)
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            errorMessage = AppErrorMessage.school("Could not load photo", error)
        }
    }

    private func saveProfile() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let avatarUrl: String?
                if let selectedAvatarData {
                    avatarUrl = try await ProfileService.shared.uploadAvatar(data: selectedAvatarData)
                } else {
                    avatarUrl = profile?.avatarUrl
                }

                let updatedProfile = try await ProfileService.shared.upsertCurrentProfile(
                    displayName: trimmedName,
                    avatarUrl: avatarUrl
                )

                await MainActor.run {
                    profile = updatedProfile
                    displayName = updatedProfile.displayName
                    selectedAvatarData = nil
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = AppErrorMessage.school("Could not save profile", error)
                }
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
                            .foregroundColor(.white)
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

        let parts = fallbackName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(parts).uppercased()
        return value.isEmpty ? "?" : value
    }
}

private struct ProfilePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.black)
            .padding(.vertical, 12)
            .background(AppConstants.Colors.accessibleYellow.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
    }
}
