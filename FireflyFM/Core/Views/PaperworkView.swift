//
//  PaperworkView.swift
//  FireflyFM
//

import SwiftUI

struct PaperworkView: View {
    var body: some View {
        AssignmentsView(surface: .paperwork)
    }
}

#Preview {
    PaperworkView()
        .environmentObject(AppSessionManager())
}
