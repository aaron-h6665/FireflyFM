import Foundation
import Observation
import SwiftUI

struct UpcomingEventsClient {
    var fetchEvents: (UUID) async throws -> [SchoolEvent]

    static let live = UpcomingEventsClient(
        fetchEvents: { schoolId in
            try await SchoolWorkflowService.shared.fetchEvents(schoolId: schoolId)
        }
    )
}

@MainActor
@Observable
final class UpcomingEventsModel {
    private let client: UpcomingEventsClient
    private let now: () -> Date
    private var requestId = UUID()

    private(set) var events: [SchoolEvent] = []
    private(set) var phase: AsyncPhase = .idle

    init() {
        client = .live
        now = Date.init
    }

    init(client: UpcomingEventsClient, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    func load(schoolId: UUID) async {
        let currentRequestId = UUID()
        requestId = currentRequestId
        phase = events.isEmpty ? .loading : .loaded

        do {
            let loadedEvents = try await client.fetchEvents(schoolId)
            guard requestId == currentRequestId else { return }
            let currentDate = now()
            events = loadedEvents
                .filter { ($0.endAt ?? $0.startAt) >= currentDate }
                .sorted { $0.startAt < $1.startAt }
            phase = events.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            return
        } catch {
            guard requestId == currentRequestId else { return }
            phase = .failed(AppErrorMessage.school("Could not load upcoming events", error))
        }
    }
}

struct UpcomingEventsSection: View {
    let schoolId: UUID?
    var onSelect: (SchoolEvent) -> Void

    @State private var model = UpcomingEventsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingSmall) {
            Label("Upcoming", systemImage: "calendar")
                .font(.headline)
                .foregroundColor(FireflyTheme.Colors.primaryText)

            if model.phase.isLoading {
                ProgressView()
                    .tint(FireflyTheme.Colors.primaryAction)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else if model.events.isEmpty {
                FireflyEmptyState(title: "No upcoming events", systemImage: "calendar")
            } else {
                ForEach(model.events.prefix(3)) { event in
                    Button {
                        onSelect(event)
                    } label: {
                        EventSummaryRow(event: event)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this event in Calendar")
                }
            }

            if case .failed(let message) = model.phase {
                FireflyInlineError(message: message)
            }
        }
        .task(id: schoolId) {
            guard let schoolId else { return }
            await model.load(schoolId: schoolId)
        }
    }
}
