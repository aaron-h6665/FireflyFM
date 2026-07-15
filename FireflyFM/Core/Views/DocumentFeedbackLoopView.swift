//
//  DocumentFeedbackLoopView.swift
//  FireflyFM
//

import SwiftUI

struct DocumentFeedbackLoopView: View {
    var body: some View {
        AssignmentsView(surface: .documents)
    }
}

#Preview {
    DocumentFeedbackLoopView()
        .environmentObject(AppSessionManager())
}
