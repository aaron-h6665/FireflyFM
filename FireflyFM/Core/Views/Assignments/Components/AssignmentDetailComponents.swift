import SwiftUI

enum AssignmentLifecycleAction: String, Identifiable {
    case close
    case archive
    var id: String { rawValue }
    var targetStatus: String { self == .close ? "closed" : "archived" }
    var title: String { self == .close ? "Close assignment?" : "Archive assignment?" }
    var message: String {
        self == .close
            ? "Recipients can still view materials, submissions, scores, and the conversation, but they cannot submit or comment until you reopen it."
            : "This moves the assignment out of active lists for everyone. It remains available under Archived and can be restored as closed."
    }
    var confirmLabel: String { self == .close ? "Close Assignment" : "Archive Assignment" }
    var icon: String { self == .close ? "lock.fill" : "archivebox.fill" }
}

struct AssignmentConfirmationOverlay: View {
    let action: AssignmentLifecycleAction
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(spacing: 16) {
                Image(systemName: action.icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                VStack(spacing: 6) {
                    Text(action.title).font(.title3.bold()).foregroundColor(AppConstants.Colors.primaryText)
                    Text(action.message)
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.64))
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                    Button(action.confirmLabel, action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(AppConstants.Colors.card)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12)))
            .cornerRadius(18)
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
            .padding()
        }
    }
}

struct AssignmentScoreRail: View {
    @Binding var score: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Score", systemImage: "star.circle.fill").font(.subheadline.bold())
                Spacer()
                Text(score.map { "\($0) / 10" } ?? "No score")
                    .font(.title3.bold())
                    .foregroundColor(AppConstants.Colors.primaryAction)
                if score != nil { Button("Clear") { score = nil }.font(.caption.bold()) }
            }
            Slider(
                value: Binding(
                    get: { Double(score ?? 5) },
                    set: { score = Int($0.rounded()) }
                ),
                in: 1...10,
                step: 1
            )
            .tint(AppConstants.Colors.accessibleYellow)
            .accessibilityLabel("Score out of ten")
            HStack {
                Text("1")
                Spacer()
                Text("5")
                Spacer()
                Text("10")
            }
            .font(.caption2.bold())
            .foregroundColor(AppConstants.Colors.secondaryText)
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }
}

struct AssignmentScoreSummary: View {
    let submission: AssignmentSubmission
    let reviewerName: String?

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(submission.score.map(String.init) ?? "—").font(.largeTitle.bold())
                Text("out of 10").font(.caption2.bold())
            }
            .foregroundColor(AppConstants.Colors.primaryAction)
            VStack(alignment: .leading, spacing: 4) {
                Text("Attempt \(submission.attemptNumber ?? 1) · \(submission.status.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(.subheadline.bold())
                if let reviewerName { Text("Reviewed by \(reviewerName)") }
                if let reviewedAt = submission.reviewedAt {
                    Text(reviewedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.caption)
            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.68))
            Spacer()
        }
        .padding()
        .background(AppConstants.Colors.background.opacity(0.45))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
    }
}

struct AssignmentScoreEditor: View {
    @Binding var score: Int?
    let attemptNumber: Int
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Update the score for attempt \(attemptNumber). The review decision and feedback will not change.")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                AssignmentScoreRail(score: $score)
                Spacer()
            }
            .padding()
            .background(AppConstants.Colors.background.ignoresSafeArea())
            .navigationTitle("Edit Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: onSave) }
            }
        }
    }
}

