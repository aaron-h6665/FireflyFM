//
//  DocumentFeedbackLoopView.swift
//  FireflyFM
//

import SwiftUI

struct DocumentFeedbackLoopView: View {
    var body: some View {
        AssignmentsView(filter: .documents)
    }
}

#Preview {
    DocumentFeedbackLoopView()
        .environmentObject(AppSessionManager())
}
