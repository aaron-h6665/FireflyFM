//
//  CurriculumView.swift
//  FireflyFM
//

import SwiftUI

struct CurriculumView: View {
    var body: some View {
        AssignmentsView(filter: .learning)
    }
}

#Preview {
    CurriculumView()
        .environmentObject(AppSessionManager())
}
