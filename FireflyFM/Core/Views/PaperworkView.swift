//
//  PaperworkView.swift
//  FireflyFM
//

import SwiftUI

struct PaperworkView: View {
    var body: some View {
        AssignmentsView(filter: .paperwork)
    }
}

#Preview {
    PaperworkView()
        .environmentObject(AppSessionManager())
}
