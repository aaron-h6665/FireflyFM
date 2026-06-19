//
//  PaymentsView.swift
//  FireflyFM
//

import SwiftUI

struct PaymentsView: View {
    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 42))
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Text("Payments")
                    .font(.title.bold())
                    .foregroundColor(.white)
                Text("Invoices, receipt summaries, and payment workflows will appear here when billing requirements are finalized.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .navigationTitle("Payments")
    }
}
