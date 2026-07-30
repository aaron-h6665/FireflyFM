import Foundation
import Observation

struct PaymentsClient {
    var fetchSetupRecords: (UUID) async throws -> [PaymentSetupRecord]

    static let live = PaymentsClient(
        fetchSetupRecords: { try await SchoolWorkflowService.shared.fetchPaymentSetupRecords(schoolId: $0) }
    )
}

@MainActor
@Observable
final class PaymentsModel {
    private let client: PaymentsClient

    private(set) var records: [PaymentSetupRecord] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() {
        client = .live
    }

    init(client: PaymentsClient) {
        self.client = client
    }

    func load(schoolId: UUID?) async {
        guard let schoolId else {
            records = []
            phase = .empty
            return
        }
        phase = .loading
        errorMessage = nil
        do {
            records = try await client.fetchSetupRecords(schoolId)
            phase = records.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) {
            phase = .idle
        } catch {
            errorMessage = AppErrorMessage.school("Could not load payment statuses", error)
            phase = .failed(errorMessage ?? "Could not load payment statuses")
        }
    }
}
