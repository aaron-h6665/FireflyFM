//
//  ContentView.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @State private var model = AppShellModel()
    @State private var showingNotificationPrimer = false
    
    var body: some View {
        Group {
            switch authManager.authState {
            case .notDetermind:
                ZStack {
                    AppConstants.Colors.background.ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                        ProgressView()
                            .tint(AppConstants.Colors.primaryAction)
                    }
                }
            case .notAuthenticated:
                NavigationStack {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        
                        // Decorative Glow
                        VStack {
                            Circle()
                                .fill(AppConstants.Colors.wingMist.opacity(0.45))
                                .frame(width: 400, height: 400)
                                .blur(radius: 60)
                                .offset(x: -150, y: -200)
                            Spacer()
                        }
                        
                        VStack(spacing: 40) {
                            Spacer()
                            
                            // Branding
                            VStack(spacing: 16) {
                                Image("Logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 140, height: 140)
                                
                                VStack(spacing: 8) {
                                    Text("FireflyFM")
                                        .font(.system(size: 38, weight: .bold, design: .rounded))
                                        .foregroundColor(AppConstants.Colors.primaryText)
                                    Text("Connecting directors, staff, and parents.")
                                        .font(.subheadline)
                                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.85)) // High contrast text
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }
                            
                            Spacer()
                            
                            // Navigation Buttons
                            VStack(spacing: 16) {
                                // Pushes to the Login View
                                NavigationLink(destination: LoginView()) {
                                    Text("Sign In")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(AppConstants.Colors.primaryAction)
                                        .foregroundColor(AppConstants.Colors.primaryActionText)
                                        .cornerRadius(12)
                                        .shadow(color: AppConstants.Colors.primaryAction.opacity(0.22), radius: 10, x: 0, y: 5)
                                }
                                
                                // Pushes to the Role Selection View
                                NavigationLink(destination: RoleSelectionView()) {
                                    Text("Create an Account")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(AppConstants.Colors.card)
                                        .foregroundColor(AppConstants.Colors.primaryText)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(AppConstants.Colors.separator, lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                        }
                    }
                }
            case .authenticated:
                if authManager.isSigningOut {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(AppConstants.Colors.accessibleYellow)
                            Text("Signing out...")
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                        }
                    }
                } else if appSession.isLoading && !appSession.hasSchoolAccess {
                    ZStack {
                        AppConstants.Colors.background.ignoresSafeArea()
                        ProgressView("Loading school")
                            .tint(AppConstants.Colors.accessibleYellow)
                            .foregroundColor(AppConstants.Colors.primaryText)
                    }
                } else if appSession.backendCompatibility == .updateRequired {
                    BackendUpdateRequiredView()
                } else if appSession.hasSchoolAccess {
                    if OnboardingAccessPolicy(context: appSession.accessContext()).usesChecklist {
                        switch appSession.activeContext?.membership.accessState {
                        case "onboarding":
                            OnboardingLimitedWorkspaceView()
                        case "full":
                            if appSession.shouldShowWelcomeExperience,
                               let role = appSession.role {
                                FireflyWelcomeExperienceView(role: role) {
                                    appSession.completeWelcomeExperience()
                                }
                            } else {
                                MainTabView()
                                    .id(appSession.activeMembershipId)
                            }
                        default:
                            // Fail closed if the backend has not returned an
                            // authoritative per-membership access state.
                            OnboardingLimitedWorkspaceView()
                        }
                    } else {
                        MainTabView()
                            .id(appSession.activeMembershipId)
                    }
                } else if let errorMessage = appSession.errorMessage {
                    SchoolAccessErrorView(message: errorMessage) {
                        Task { await appSession.refresh() }
                    } onSignOut: {
                        Task { await authManager.signOut() }
                    }
                } else {
                    SchoolWelcomeView()
                }
            }
        }
        .task {
            await authManager.getAuthState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && authManager.authState == .authenticated {
                Task { await appSession.refresh(selecting: appSession.activeMembershipId) }
            }
        }
        .task(id: authManager.authState) {
            switch authManager.authState {
            case .authenticated:
                await appSession.refresh()
                await model.prepareNotifications()
                if appSession.hasSchoolAccess,
                   await PushNotificationManager.shared.shouldOfferPermissionPrimer() {
                    showingNotificationPrimer = true
                }
            case .notAuthenticated:
                appSession.clear()
            case .notDetermind:
                break
            }
        }
        .sheet(item: membershipInviteBinding) { invite in
            InviteCoordinatorView(invite: invite)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingNotificationPrimer) {
            NotificationPermissionPrimerView {
                showingNotificationPrimer = false
            }
        }
    }

    private var membershipInviteBinding: Binding<PendingInvite?> {
        Binding(
            get: {
                authManager.authState == .authenticated
                    ? deepLinkManager.pendingMembershipInvite
                    : nil
            },
            set: { _ in }
        )
    }
}

private struct FireflyWelcomeExperienceView: View {
    let role: SchoolRole
    let onFinish: () -> Void
    @State private var page = 0

    private var pages: [FireflyWelcomePage] {
        switch role {
        case .parent:
            [
                .init(symbol: "sun.max.fill", title: "Start with Today", body: "See the updates and school news that matter to your family."),
                .init(symbol: "calendar.badge.clock", title: "Plan with Calendar", body: "Open Calendar to see upcoming school events, dates, and details in one place."),
                .init(symbol: "square.grid.2x2.fill", title: "Your family workspace", body: "Workspace brings together child information, family requests, payments, and the tools you use less often."),
                .init(symbol: "bubble.left.and.bubble.right.fill", title: "Stay connected", body: "Message your school and keep shared photos, files, and replies together in the app.")
            ]
        case .teacher:
            [
                .init(symbol: "sun.max.fill", title: "Start with Today", body: "See what needs attention and move quickly into your classroom work."),
                .init(symbol: "checkmark.circle.fill", title: "Record the day", body: "Take attendance and add care updates while the details are fresh."),
                .init(symbol: "bubble.left.and.bubble.right.fill", title: "Keep families close", body: "Share moments, respond to family requests, and keep conversations in context.")
            ]
        case .schoolDirector:
            [
                .init(symbol: "sun.max.fill", title: "Your school at a glance", body: "Today brings important school activity and operational follow-up into one place."),
                .init(symbol: "person.crop.circle.badge.checkmark", title: "Guide your community", body: "Invite families and teachers, review setup work, and see who is ready for access."),
                .init(symbol: "rectangle.3.group.fill", title: "Run the school", body: "Manage children, classrooms, billing, messages, events, and newsletters from your workspace.")
            ]
        case .hqDirector:
            []
        }
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            Circle()
                .fill(AppConstants.Colors.wingMist.opacity(0.42))
                .frame(width: 380, height: 380)
                .blur(radius: 55)
                .offset(x: -150, y: -280)

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button("Skip") { onFinish() }
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                }
                .padding(.horizontal, 22)

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .accessibilityLabel("FireflyFM logo")

                VStack(spacing: 5) {
                    Text("Welcome to FireflyFM")
                        .font(.largeTitle.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text("Your setup is complete. Here’s a quick look at your \(role.title.lowercased()) workspace.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        welcomeCard(item)
                            .tag(index)
                            .padding(.horizontal, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(page == pages.count - 1 ? "Start using FireflyFM" : "Next") {
                    if page == pages.count - 1 {
                        onFinish()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(SchoolAccessPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .accessibilityIdentifier("welcome.continue")
            }
            .padding(.top, 10)
        }
    }

    private func welcomeCard(_ item: FireflyWelcomePage) -> some View {
        VStack(spacing: 18) {
            Image(systemName: item.symbol)
                .font(.system(size: 46, weight: .semibold))
                .foregroundColor(AppConstants.Colors.brandNavy)
                .frame(width: 94, height: 94)
                .background(AppConstants.Colors.accessibleYellow)
                .clipShape(Circle())
            Text(item.title)
                .font(.title2.bold())
                .foregroundColor(AppConstants.Colors.primaryText)
            Text(item.body)
                .font(.body)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppConstants.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.vertical, 18)
    }
}

private struct FireflyWelcomePage {
    let symbol: String
    let title: String
    let body: String
}

private struct BackendUpdateRequiredView: View {
    @EnvironmentObject private var appSession: AppSessionManager
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "server.rack")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Text("Backend update required")
                    .font(.title2.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                Text("FireflyFM needs the verified database migrations before school data can be loaded.")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button("Check Again") { Task { await appSession.refresh() } }
                    .buttonStyle(.borderedProminent)
                Button("Sign Out") { Task { await authManager.signOut() } }
                    .buttonStyle(.bordered)
            }
            .padding(28)
        }
    }
}

private struct SchoolAccessErrorView: View {
    var message: String
    var onRetry: () -> Void
    var onSignOut: () -> Void

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)

                Text("Could not load school access")
                    .font(.title.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.75))

                VStack(spacing: 12) {
                    Button(action: onRetry) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SchoolAccessPrimaryButtonStyle())

                    Button(action: onSignOut) {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SchoolAccessSecondaryButtonStyle())
                }
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppConstants.Colors.card)
            .cornerRadius(12)
            .padding(24)
        }
    }
}

private struct SchoolAccessPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(AppConstants.Colors.primaryActionText)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 18)
            .background(AppConstants.Colors.primaryAction.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SchoolAccessSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(AppConstants.Colors.primaryText)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.1))
            .cornerRadius(8)
    }
}
