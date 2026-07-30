import SwiftUI

struct ChildReportsView: View {
    let child: Child
    @State private var model = ChildReportsModel()

    var body: some View {
        FireflyScreen {
            ScrollView {
                VStack(spacing: FireflyTheme.Layout.spacingMedium) {
                    if model.phase.isLoading {
                        ProgressView("Loading reports")
                    } else if model.reports.isEmpty {
                        FireflyEmptyState(
                            title: "No progress reports",
                            message: "Approved and released reports will appear here.",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    } else {
                        ForEach(model.reports) { report in
                            FireflySectionCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(report.title, systemImage: "doc.text")
                                        .font(.headline)
                                    if let body = report.body?.nilIfBlank {
                                        Text(body)
                                            .font(.subheadline)
                                            .foregroundColor(AppConstants.Colors.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                    if let error = model.errorMessage {
                        FireflyInlineError(message: error)
                        Button("Retry") { Task { await model.load(childId: child.id) } }
                            .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Progress Reports")
        .task(id: child.id) { await model.load(childId: child.id) }
    }
}
