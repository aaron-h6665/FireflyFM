//
//  CurriculumView.swift
//  FireflyFM
//

import SwiftUI

struct CurriculumView: View {
    var body: some View {
        AssignmentsView(surface: .curriculum)
    }
}

#Preview {
    CurriculumView()
        .environmentObject(AppSessionManager())
}
