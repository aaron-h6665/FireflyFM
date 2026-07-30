import SwiftUI

struct ParentWorkspaceView: View {
    var body: some View {
        RoleWorkspaceScaffold(
            subtitle: "Everything about your child and school outside of Messages."
        ) {
            WorkspaceLink(
                title: "My Children",
                subtitle: "Profiles, progress, and school records",
                systemImage: "figure.2.and.child.holdinghands",
                destination: ChildrenView()
            )
            WorkspaceLink(
                title: "Family Requests",
                subtitle: "Absence, pickup, and other school needs",
                systemImage: "person.crop.circle.badge.questionmark",
                destination: FamilyRequestsView()
            )
            WorkspaceLink(
                title: "Paperwork",
                subtitle: "Forms and school requests",
                systemImage: "doc.text.fill",
                destination: AssignmentsView(filter: .all)
            )
            WorkspaceLink(
                title: "Payments",
                subtitle: "Invoices, payments, and receipts",
                systemImage: "creditcard.fill",
                destination: PaymentsView()
            )
            WorkspaceLink(
                title: "School Community",
                subtitle: "Newsletters, albums, and school updates",
                systemImage: "person.3.fill",
                destination: CommunityRootView()
            )
        }
    }
}

struct TeacherWorkspaceView: View {
    var body: some View {
        RoleWorkspaceScaffold(
            subtitle: "Less-frequent classroom tools stay organized here."
        ) {
            WorkspaceLink(
                title: "Training & Curriculum",
                subtitle: "Required learning and school work",
                systemImage: "graduationcap.fill",
                destination: AssignmentsView(filter: .learning)
            )
            WorkspaceLink(
                title: "Children",
                subtitle: "Child profiles and classroom context",
                systemImage: "figure.2.and.child.holdinghands",
                destination: ChildrenView()
            )
            WorkspaceLink(
                title: "School Community",
                subtitle: "Posts, albums, and school information",
                systemImage: "person.3.fill",
                destination: CommunityRootView()
            )
        }
    }
}

struct SchoolDirectorWorkspaceView: View {
    var body: some View {
        RoleWorkspaceScaffold(
            subtitle: "School administration and oversight tools."
        ) {
            WorkspaceLink(
                title: "Children & Attendance",
                subtitle: "Manage rosters, identity, and attendance history",
                systemImage: "person.2.crop.square.stack.fill",
                destination: ChildrenAttendanceWorkspace()
            )
            WorkspaceLink(
                title: "People & Access",
                subtitle: "Invitations, onboarding, and school access",
                systemImage: "person.badge.key.fill",
                destination: SchoolDirectorAccessWorkspace()
            )
            WorkspaceLink(
                title: "Assignments & Training",
                subtitle: "Manage school work and complete assigned training",
                systemImage: "checklist",
                destination: AssignmentsView(filter: .all)
            )
            WorkspaceLink(
                title: "School Community",
                subtitle: "Newsletters, posts, albums, and information",
                systemImage: "person.3.fill",
                destination: CommunityRootView()
            )
        }
    }
}

struct HQDirectorWorkspaceView: View {
    var body: some View {
        RoleWorkspaceScaffold(
            subtitle: "Cross-school administration and reporting tools."
        ) {
            WorkspaceLink(
                title: "Schools",
                subtitle: "School-by-school operational overview",
                systemImage: "building.2.fill",
                destination: HQSchoolsView()
            )
            WorkspaceLink(
                title: "Children & Attendance",
                subtitle: "Cross-school roster, attendance, and history",
                systemImage: "person.2.crop.square.stack.fill",
                destination: ChildrenAttendanceWorkspace()
            )
            WorkspaceLink(
                title: "Training & Curriculum",
                subtitle: "Staff learning across schools",
                systemImage: "graduationcap.fill",
                destination: AssignmentsView(filter: .learning, schoolSelection: .selectable)
            )
            WorkspaceLink(
                title: "Communities",
                subtitle: "Open a school's community space",
                systemImage: "person.3.fill",
                destination: CommunityRootView()
            )
        }
    }
}

private struct RoleWorkspaceScaffold<Content: View>: View {
    let subtitle: String
    private let content: Content

    init(subtitle: String, @ViewBuilder content: () -> Content) {
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            FireflyScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingMedium) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(FireflyTheme.Colors.secondaryText)
                        content
                    }
                    .padding(FireflyTheme.Layout.cardPadding)
                }
            }
            .navigationTitle("Workspace")
        }
    }
}

struct ChildrenAttendanceWorkspace: View {
    private enum Section: String, CaseIterable, Identifiable {
        case roster = "Roster"
        case attendance = "Attendance"

        var id: String { rawValue }
    }

    @State private var section: Section = .roster

    var body: some View {
        VStack(spacing: 0) {
            Picker("Children and attendance", selection: $section) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, FireflyTheme.Layout.spacingSmall)
            .background(FireflyTheme.Colors.background)

            switch section {
            case .roster:
                ChildrenView(navigationTitle: "Children & Attendance")
            case .attendance:
                AttendanceView(navigationTitle: "Children & Attendance")
            }
        }
        .background(FireflyTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Children & Attendance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SchoolDirectorAccessWorkspace: View {
    @EnvironmentObject private var appSession: AppSessionManager

    var body: some View {
        if let school = appSession.activeSchool {
            OnboardingManagementView(school: school, mode: .schoolDirector)
        } else {
            ContentUnavailableView("No active school", systemImage: "building.2")
        }
    }
}
