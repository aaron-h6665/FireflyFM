import SwiftUI

struct CommunityRootView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @State private var hqSchools: [School] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if appSession.role == .hqDirector {
                    hqSchoolPicker
                } else if let school = appSession.activeSchool {
                    CommunityView(school: school)
                        .id(school.id)
                } else {
                    ContentUnavailableView("No active school", systemImage: "building.2")
                }
            }
            .background(AppConstants.Colors.background.ignoresSafeArea())
        }
        .task(id: appSession.activeMembershipId) {
            guard appSession.role == .hqDirector else { return }
            await loadSchools()
        }
    }

    private var hqSchoolPicker: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("School Communities")
                    .font(.largeTitle.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text("Choose a school to view its private feed, albums, and information.")
                    .foregroundColor(AppConstants.Colors.secondaryText)

                if isLoading {
                    ProgressView().tint(AppConstants.Colors.primaryAction)
                } else {
                    ForEach(hqSchools) { school in
                        NavigationLink {
                            CommunityView(school: school)
                        } label: {
                            HStack(spacing: 14) {
                                SchoolAvatarView(school: school, size: 52)
                                Text(school.name)
                                    .font(.headline)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(AppConstants.Colors.fireflyBlue)
                            }
                            .padding()
                            .background(AppConstants.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .padding()
        }
    }

    @MainActor
    private func loadSchools() async {
        isLoading = true
        do {
            hqSchools = try await SchoolService.shared.fetchSchoolsForHQ()
            errorMessage = nil
        } catch {
            errorMessage = AppErrorMessage.school("Could not load school communities", error)
        }
        isLoading = false
    }
}
