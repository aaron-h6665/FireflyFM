//
//  PaymentsView.swift
//  FireflyFM
//

import SwiftUI

struct PaymentsView: View {
    @EnvironmentObject private var appSession: AppSessionManager

    @State private var model = PaymentsModel()

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Payments")
                        .font(.largeTitle.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text(AppConstants.Features.paymentsEnabled
                         ? "Payment setup is a verification checklist. No bank account, autopay, ACH, or payment credentials are stored directly in FireflyFM."
                         : "Payment setup is waived for MVP testing. No bank account, autopay, ACH, or payment credentials are collected in this build.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.65))

                    if model.phase.isLoading {
                        ProgressView()
                            .tint(AppConstants.Colors.accessibleYellow)
                    } else if model.records.isEmpty {
                        ForEach(defaultStatuses, id: \.0) { item in
                            statusCard(title: item.0, status: item.1, notes: item.2)
                        }
                    } else {
                        ForEach(model.records) { record in
                            statusCard(
                                title: record.paymentType.replacingOccurrences(of: "_", with: " ").capitalized,
                                status: record.status,
                                notes: record.notes ?? "Status updated \(record.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "recently")."
                            )
                        }
                    }

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Payments")
        .task { await load() }
        .refreshable { await load() }
    }

    private var defaultStatuses: [(String, String, String)] {
        let policy = PaymentAccessPolicy(context: appSession.accessContext())
        if policy.usesSchoolSetupPresentation {
            return [
                ("Payment Setup", AppConstants.Features.paymentsEnabled ? "needs_setup" : "waived", "Payment-provider integration is intentionally deferred for the MVP."),
                ("Autopay Readiness", AppConstants.Features.paymentsEnabled ? "needs_setup" : "waived", "Bank linking is intentionally not implemented in this phase.")
            ]
        }
        return [
            ("Tuition Setup", AppConstants.Features.paymentsEnabled ? "needs_setup" : "waived", "Payment-provider integration will be added after requirements are finalized."),
            ("Statements", AppConstants.Features.paymentsEnabled ? "needs_setup" : "waived", "Invoices and receipt summaries will appear here later.")
        ]
    }

    private func statusCard(title: String, status: String, notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.brandNavy)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(status))
                    .clipShape(Capsule())
            }
            Text(notes)
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.66))
        }
        .padding()
        .background(AppConstants.Colors.card)
        .cornerRadius(8)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "verified", "sandbox_verified": return .green
        case "waived": return .cyan
        case "flagged": return .red
        case "submitted": return .orange
        default: return AppConstants.Colors.accessibleYellow
        }
    }

    @MainActor
    private func load() async {
        await model.load(schoolId: appSession.activeSchool?.id)
    }
}
