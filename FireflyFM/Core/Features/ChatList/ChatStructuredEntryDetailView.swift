import SwiftUI

struct ChatStructuredEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let sourceType: String
    let sourceId: UUID
    let canHandleFamilyRequest: Bool

    @State private var model = ChatStructuredEntryModel()

    private var careEvent: ChildCareEvent? { model.careEvent }
    private var familyRequest: FamilyRequest? { model.familyRequest }
    private var isLoading: Bool { model.phase.isLoading }
    private var isUpdating: Bool { model.isUpdating }
    private var errorMessage: String? { model.errorMessage }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                Group {
                    if isLoading {
                        ProgressView("Opening update")
                    } else if let careEvent {
                        careDetail(careEvent)
                    } else if let familyRequest {
                        requestDetail(familyRequest)
                    } else {
                        ContentUnavailableView(
                            "Update unavailable",
                            systemImage: "exclamationmark.bubble.fill",
                            description: Text(errorMessage ?? "This update may no longer be available.")
                        )
                    }
                }
            }
            .navigationTitle(sourceType == "child_care_events" ? "Daily Activity" : "Family Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func careDetail(_ event: ChildCareEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(title: event.eventType.title, symbol: event.eventType.symbol, date: event.occurredAt)
                detailValues(event.details, excluding: ["photo_path"])
                if !event.developmentalDomains.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Development Areas").font(.caption.bold()).foregroundColor(AppConstants.Colors.secondaryText)
                        ForEach(event.developmentalDomains, id: \.self) { rawValue in
                            if let domain = ChildDevelopmentalDomain(rawValue: rawValue) {
                                Label(domain.title, systemImage: domain.symbol)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppConstants.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if event.reportHighlight {
                    Label("Progress Highlight", systemImage: "star.circle.fill")
                        .font(.caption.bold()).foregroundColor(AppConstants.Colors.primaryAction)
                }
                if event.visibility == "staff_only" {
                    Label("Staff Only", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                }
            }
            .padding()
        }
    }

    private func requestDetail(_ request: FamilyRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(
                    title: request.requestType.replacingOccurrences(of: "_", with: " ").capitalized,
                    symbol: "person.crop.circle.badge.questionmark",
                    date: request.createdAt
                )
                Text(request.status.capitalized)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppConstants.Colors.wingMist)
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .clipShape(Capsule())
                detailValues(request.details)

                if canHandleFamilyRequest {
                    HStack {
                        Button("Acknowledge") { updateRequest(request, status: "acknowledged") }
                            .buttonStyle(.bordered)
                        Button("Complete") { updateRequest(request, status: "completed") }
                            .buttonStyle(.borderedProminent)
                    }
                    .tint(AppConstants.Colors.primaryAction)
                    .disabled(isUpdating)
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.red)
                }
            }
            .padding()
        }
    }

    private func detailHeader(title: String, symbol: String, date: Date) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundColor(AppConstants.Colors.brandNavy)
                .frame(width: 50, height: 50)
                .background(AppConstants.Colors.fireflyGlow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.bold()).foregroundColor(AppConstants.Colors.primaryText)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
            }
        }
    }

    private func detailValues(_ values: [String: FireflyJSONValue], excluding excluded: Set<String> = []) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(values.keys.sorted().filter { !excluded.contains($0) }, id: \.self) { key in
                if let value = values[key]?.stringValue, !value.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.secondaryText)
                        Text(value).foregroundColor(AppConstants.Colors.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppConstants.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    @MainActor
    private func load() async {
        await model.load(sourceType: sourceType, sourceId: sourceId)
    }

    private func updateRequest(_ request: FamilyRequest, status: String) {
        Task { await model.update(request, status: status) }
    }
}
